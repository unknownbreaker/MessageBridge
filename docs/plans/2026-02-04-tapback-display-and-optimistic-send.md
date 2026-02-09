# Tapback Display & Optimistic Send Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make tapback reactions visible on message bubbles and give instant feedback when sending them.

**Architecture:** Two independent changes: (1) render `.topTrailing` decorators in `MessageBubble` so `TapbackDecorator`/`TapbackPill` actually shows, (2) add optimistic local state updates in `MessagesViewModel.sendTapback()` with rollback on failure. Server route returns richer response with tapback data.

**Tech Stack:** SwiftUI, Vapor 4, Swift actors

---

### Task 1: Render `.topTrailing` Decorators in MessageBubble

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift:196-246`

Currently `MessageBubble` only renders decorators at `.below` (line 230) and `.bottomTrailing` (line 239). The `TapbackDecorator` is registered at `.topTrailing` but never rendered.

**Step 1: Add `.topTrailing` decorator rendering**

In `MessageBubble.body`, wrap the VStack content in a ZStack to overlay `.topTrailing` decorators. The key change is around lines 196-246:

```swift
// Inside MessageBubble body, replace the existing VStack with:
VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
  // Show sender name in group conversations when sender changes
  if isGroupConversation && !message.isFromMe && showSenderInfo {
    Text(sender?.displayName ?? "Unknown")
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.leading, 4)
  }

  // Message content with topTrailing overlay for tapbacks
  ZStack(alignment: .topTrailing) {
    VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
      // Display attachments first (like Apple Messages)
      if message.hasAttachments {
        AttachmentRendererRegistry.shared.renderer(for: message.attachments)
          .render(message.attachments)
      }

      // Display text if present - delegated to RendererRegistry
      if message.hasText || message.linkPreview != nil {
        let renderer = RendererRegistry.shared.renderer(for: message)
        let isLinkPreview = message.linkPreview != nil

        renderer.render(message)
          .padding(.horizontal, isLinkPreview ? 0 : 12)
          .padding(.vertical, isLinkPreview ? 0 : 8)
          .background(message.isFromMe ? Color.blue : Color(.systemGray).opacity(0.2))
          .foregroundStyle(message.isFromMe ? .white : .primary)
          .clipShape(RoundedRectangle(cornerRadius: 16))
      }
    }

    // Top trailing decorators (tapback pills)
    let decoratorContext = DecoratorContext(
      isLastSentMessage: isLastSentMessage,
      isLastMessage: isLastMessage,
      conversationId: message.conversationId
    )
    ForEach(
      DecoratorRegistry.shared.decorators(for: message, at: .topTrailing, context: decoratorContext),
      id: \.id
    ) { decorator in
      decorator.decorate(message, context: decoratorContext)
    }
  }

  // Below and bottom trailing decorators (unchanged)
  let decoratorContext = DecoratorContext(...)
  // ... existing .below and .bottomTrailing code ...
}
```

Note: The `decoratorContext` is used in two places now. Extract it once before the ZStack to avoid duplication.

**Step 2: Build and verify**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 3: Run client tests**

Run: `cd MessageBridgeClient && swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift
git commit -m "fix(client): render topTrailing decorators in MessageBubble for tapback pills"
```

---

### Task 2: Add Optimistic Tapback State Updates in ViewModel

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift:475-488`

The current `sendTapback()` (line 480) fires and forgets — no local state change. We need to:
1. Find the message in local cache
2. Optimistically update its tapbacks
3. Send request to server
4. Roll back on failure

**Step 1: Rewrite `sendTapback` with optimistic updates**

Replace the existing `sendTapback` method (lines 475-488) with:

```swift
/// Send a tapback reaction to a message
public func sendTapback(
  type: TapbackType,
  messageGUID: String,
  conversationId: String,
  action: TapbackActionType
) async {
  // Find the message in local cache
  guard var conversationMessages = messages[conversationId],
        let messageIndex = conversationMessages.firstIndex(where: { $0.guid == messageGUID })
  else {
    logWarning("sendTapback: message \(messageGUID) not found in conversation \(conversationId)")
    return
  }

  let message = conversationMessages[messageIndex]
  let previousTapbacks = message.tapbacks

  // Optimistic update
  var tapbacks = message.tapbacks ?? []

  if action == .remove {
    tapbacks.removeAll { $0.isFromMe && $0.type == type }
  } else {
    // Remove any existing tapback from me first (one tapback per user)
    tapbacks.removeAll { $0.isFromMe }
    let newTapback = Tapback(
      type: type,
      sender: "me",
      isFromMe: true,
      date: Date(),
      messageGUID: messageGUID
    )
    tapbacks.append(newTapback)
  }

  // Apply optimistic update
  let updatedMessage = Message(
    id: message.id,
    guid: message.guid,
    text: message.text,
    date: message.date,
    isFromMe: message.isFromMe,
    handleId: message.handleId,
    conversationId: message.conversationId,
    attachments: message.attachments,
    detectedCodes: message.detectedCodes,
    highlights: message.highlights,
    mentions: message.mentions,
    tapbacks: tapbacks.isEmpty ? nil : tapbacks,
    dateDelivered: message.dateDelivered,
    dateRead: message.dateRead,
    linkPreview: message.linkPreview
  )
  conversationMessages[messageIndex] = updatedMessage
  messages[conversationId] = conversationMessages

  // Send to server
  do {
    try await bridgeService.sendTapback(type: type, messageGUID: messageGUID, action: action)
    logDebug("Tapback \(action.rawValue) sent successfully for message \(messageGUID)")
  } catch {
    // Rollback on failure
    logError("Failed to send tapback, rolling back", error: error)
    if var rollbackMessages = messages[conversationId],
       let rollbackIndex = rollbackMessages.firstIndex(where: { $0.guid == messageGUID }) {
      let rollbackMessage = Message(
        id: message.id,
        guid: message.guid,
        text: message.text,
        date: message.date,
        isFromMe: message.isFromMe,
        handleId: message.handleId,
        conversationId: message.conversationId,
        attachments: message.attachments,
        detectedCodes: message.detectedCodes,
        highlights: message.highlights,
        mentions: message.mentions,
        tapbacks: previousTapbacks,
        dateDelivered: message.dateDelivered,
        dateRead: message.dateRead,
        linkPreview: message.linkPreview
      )
      rollbackMessages[rollbackIndex] = rollbackMessage
      messages[conversationId] = rollbackMessages
    }
    lastError = error
  }
}
```

**Step 2: Update the call site in MessageThreadView**

The `sendTapback` signature changed — it now requires `conversationId`. Update `MessageThreadView.swift` line 134-139:

```swift
TapbackPicker(message: message) { type, isRemoval in
  Task {
    await viewModel.sendTapback(
      type: type,
      messageGUID: message.guid,
      conversationId: message.conversationId,
      action: isRemoval ? .remove : .add
    )
  }
}
```

**Step 3: Build and verify**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 4: Run client tests**

Run: `cd MessageBridgeClient && swift test`
Expected: All tests pass (existing tests don't call `sendTapback` with the new signature — `MockBridgeService.sendTapback` signature is unchanged at the protocol level)

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift
git commit -m "feat(client): add optimistic tapback updates with rollback on failure"
```

---

### Task 3: Enrich Server Tapback Response

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/API/APIResponses.swift:106-115`
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/API/Routes.swift:186-218`

The server currently returns `TapbackResponse(success: true, error: nil)`. Enrich it to return the tapback data so the client has confirmation.

**Step 1: Add tapback fields to TapbackResponse**

In `APIResponses.swift`, update `TapbackResponse`:

```swift
public struct TapbackResponse: Content {
  public let success: Bool
  public let error: String?
  public let messageGUID: String?
  public let tapbackType: String?
  public let action: String?

  public init(
    success: Bool,
    error: String? = nil,
    messageGUID: String? = nil,
    tapbackType: String? = nil,
    action: String? = nil
  ) {
    self.success = success
    self.error = error
    self.messageGUID = messageGUID
    self.tapbackType = tapbackType
    self.action = action
  }
}
```

**Step 2: Return tapback data in Routes.swift**

Update the tapback route (line 217) to return the enriched response:

```swift
return TapbackResponse(
  success: true,
  error: nil,
  messageGUID: messageId,
  tapbackType: tapbackRequest.type,
  action: tapbackRequest.action
)
```

**Step 3: Build and run server tests**

Run: `cd MessageBridgeServer && swift build && swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/API/APIResponses.swift
git add MessageBridgeServer/Sources/MessageBridgeCore/API/Routes.swift
git commit -m "feat(server): enrich tapback response with message GUID and type"
```

---

### Task 4: Full Verification

**Step 1: Run all tests**

Run: `cd MessageBridgeServer && swift test && cd ../MessageBridgeClient && swift test`
Expected: All server + client tests pass

**Step 2: Commit any fixes if needed**

**Step 3: Update spec.md and CLAUDE.md**

Mark the "Current Focus" section in CLAUDE.md to reflect work done this session.
