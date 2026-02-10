# Reply-to-Message Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add inline reply-to-message functionality matching iMessage's native reply UX — both displaying received replies and sending new replies.

**Architecture:** Extend the existing `Message` model on both server and client with reply metadata fields from chat.db. Display replies via a new `ReplyPreviewDecorator` (BubbleDecorator). Compose replies via a banner above the composer triggered by the existing `ReplyAction`. Send replies via AppleScript UI automation (right-click → Reply → type → send).

**Tech Stack:** Swift, Vapor, GRDB, SwiftUI, AppleScript

---

### Task 1: Server — Add reply fields to Message model

**Files:**
- Modify: `Server/Sources/MessageBridgeCore/Models/Message.swift:5-36`
- Test: `Server/Tests/MessageBridgeCoreTests/Models/MessageReplyTests.swift` (new)

**Step 1: Write the failing test**

Create `Server/Tests/MessageBridgeCoreTests/Models/MessageReplyTests.swift`:

```swift
import XCTest
@testable import MessageBridgeCore

final class MessageReplyTests: XCTestCase {

  private func makeMessage(
    replyToGuid: String? = nil,
    threadOriginatorGuid: String? = nil
  ) -> Message {
    Message(
      id: 1, guid: "msg-001", text: "Hello", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1",
      replyToGuid: replyToGuid,
      threadOriginatorGuid: threadOriginatorGuid
    )
  }

  func testMessage_replyFieldsDefaultToNil() {
    let msg = makeMessage()
    XCTAssertNil(msg.replyToGuid)
    XCTAssertNil(msg.threadOriginatorGuid)
  }

  func testMessage_replyFieldsStoreValues() {
    let msg = makeMessage(
      replyToGuid: "reply-guid",
      threadOriginatorGuid: "thread-guid"
    )
    XCTAssertEqual(msg.replyToGuid, "reply-guid")
    XCTAssertEqual(msg.threadOriginatorGuid, "thread-guid")
  }

  func testMessage_codableRoundTrip_withReplyFields() throws {
    let msg = makeMessage(
      replyToGuid: "reply-guid",
      threadOriginatorGuid: "thread-guid"
    )
    let data = try JSONEncoder().encode(msg)
    let decoded = try JSONDecoder().decode(Message.self, from: data)
    XCTAssertEqual(decoded.replyToGuid, "reply-guid")
    XCTAssertEqual(decoded.threadOriginatorGuid, "thread-guid")
  }

  func testMessage_codableRoundTrip_withoutReplyFields() throws {
    let msg = makeMessage()
    let data = try JSONEncoder().encode(msg)
    let decoded = try JSONDecoder().decode(Message.self, from: data)
    XCTAssertNil(decoded.replyToGuid)
    XCTAssertNil(decoded.threadOriginatorGuid)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd Server && swift test --filter MessageReplyTests 2>&1 | head -30`
Expected: FAIL — `replyToGuid` parameter doesn't exist on `Message.init`

**Step 3: Write minimal implementation**

In `Server/Sources/MessageBridgeCore/Models/Message.swift`, add two fields to the struct (after line 17, before `init`):

```swift
public let replyToGuid: String?
public let threadOriginatorGuid: String?
```

Update the `init` to include:

```swift
public init(
  id: Int64, guid: String, text: String?, date: Date, isFromMe: Bool, handleId: Int64?,
  conversationId: String, attachments: [Attachment] = [], tapbacks: [Tapback] = [],
  dateDelivered: Date? = nil, dateRead: Date? = nil, linkPreview: LinkPreview? = nil,
  replyToGuid: String? = nil, threadOriginatorGuid: String? = nil
) {
  // ... existing assignments ...
  self.replyToGuid = replyToGuid
  self.threadOriginatorGuid = threadOriginatorGuid
}
```

**Step 4: Run test to verify it passes**

Run: `cd Server && swift test --filter MessageReplyTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Server/Sources/MessageBridgeCore/Models/Message.swift Server/Tests/MessageBridgeCoreTests/Models/MessageReplyTests.swift
git commit -m "feat(server): add replyToGuid and threadOriginatorGuid to Message model"
```

---

### Task 2: Server — Add ProcessedMessage convenience accessor

**Files:**
- Modify: `Server/Sources/MessageBridgeCore/Models/ProcessedMessage.swift:67-71`

**Step 1: No separate test needed** — ProcessedMessage just forwards to `message`. Existing ProcessedMessage Codable test covers round-trip.

**Step 2: Add convenience accessors**

In `ProcessedMessage.swift`, add after line 71 (after `dateRead` accessor):

```swift
/// Reply-to GUID (forwards to underlying message)
public var replyToGuid: String? { message.replyToGuid }

/// Thread originator GUID (forwards to underlying message)
public var threadOriginatorGuid: String? { message.threadOriginatorGuid }
```

**Step 3: Build to verify**

Run: `cd Server && swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Server/Sources/MessageBridgeCore/Models/ProcessedMessage.swift
git commit -m "feat(server): add reply field accessors to ProcessedMessage"
```

---

### Task 3: Server — Read reply fields from chat.db

**Files:**
- Modify: `Server/Sources/MessageBridgeCore/Database/ChatDatabase.swift:194-212, 283-302, 444-461`

**Step 1: No unit test** — these are SQL queries against the real chat.db. Existing integration tests cover the query structure. We'll verify by building.

**Step 2: Update `fetchMessagesFromDB` SQL (line 194)**

Add `m.thread_originator_guid` to the SELECT and pass it through in the Message constructor:

SQL change (add after `m.payload_data` on line 204):
```sql
m.thread_originator_guid
```

Message constructor change (around line 260-270), add:
```swift
replyToGuid: row["thread_originator_guid"]
```

**Note:** We use `thread_originator_guid` (not `reply_to_guid`) because `thread_originator_guid` is the field iMessage actually populates for inline replies. `reply_to_guid` is often NULL even on replies.

**Step 3: Update `fetchMessagesNewerThan` SQL (line 283)**

Add `m.thread_originator_guid` to SELECT (after `h.id as sender_address`).

Message constructor change (around line 329-337), add:
```swift
replyToGuid: row["thread_originator_guid"]
```

**Step 4: Update `searchMessagesFromDB` SQL (line 444)**

Add `m.thread_originator_guid` to SELECT (after `c.chat_identifier as conversation_id`).

Message constructor change (around line 483-491), add:
```swift
replyToGuid: row["thread_originator_guid"]
```

**Step 5: Build to verify**

Run: `cd Server && swift build`
Expected: Build succeeds

**Step 6: Run full test suite**

Run: `cd Server && swift test`
Expected: All tests pass

**Step 7: Commit**

```bash
git add Server/Sources/MessageBridgeCore/Database/ChatDatabase.swift
git commit -m "feat(server): read thread_originator_guid from chat.db queries"
```

---

### Task 4: Server — Add replyToGuid to SendMessageRequest

**Files:**
- Modify: `Server/Sources/MessageBridgeCore/API/APIResponses.swift:58-69`
- Modify: `Server/Sources/MessageBridgeCore/Messaging/MessageSenderProtocol.swift:4-11`
- Modify: `Server/Sources/MessageBridgeCore/Messaging/AppleScriptMessageSender.swift:9-31`
- Modify: `Server/Sources/MessageBridgeCore/API/Routes.swift:250-255`
- Modify: `Server/Tests/MessageBridgeCoreTests/APITests.swift` (update MockMessageSender)

**Step 1: Update `SendMessageRequest` (APIResponses.swift:58-69)**

Add `replyToGuid` field:

```swift
public struct SendMessageRequest: Content {
  public let to: String
  public let text: String
  public let service: String?
  public let replyToGuid: String?

  public init(to: String, text: String, service: String? = nil, replyToGuid: String? = nil) {
    self.to = to
    self.text = text
    self.service = service
    self.replyToGuid = replyToGuid
  }
}
```

**Step 2: Update `MessageSenderProtocol` (MessageSenderProtocol.swift:11)**

Add `replyToGuid` parameter:

```swift
func sendMessage(to recipient: String, text: String, service: String?, replyToGuid: String?) async throws -> SendResult
```

**Step 3: Update `AppleScriptMessageSender` (AppleScriptMessageSender.swift:9-31)**

Update method signature to accept `replyToGuid`:

```swift
public func sendMessage(to recipient: String, text: String, service: String?, replyToGuid: String? = nil) async throws -> SendResult
```

(The AppleScript reply-send implementation comes in Task 5. For now, `replyToGuid` is accepted but not yet used in the script.)

**Step 4: Update `/send` route (Routes.swift:250-255)**

Pass `replyToGuid` through:

```swift
let result = try await messageSender.sendMessage(
  to: sendRequest.to,
  text: sendRequest.text,
  service: sendRequest.service,
  replyToGuid: sendRequest.replyToGuid
)
```

**Step 5: Update `MockMessageSender` in test files**

In `Server/Tests/MessageBridgeCoreTests/APITests.swift`, find the `MockMessageSender` class and update its `sendMessage` signature to match the new protocol:

```swift
func sendMessage(to recipient: String, text: String, service: String?, replyToGuid: String? = nil) async throws -> SendResult
```

Also update any other mock implementations (check `WebSocketTests.swift` and audit test files).

**Step 6: Build and test**

Run: `cd Server && swift test`
Expected: All tests pass

**Step 7: Commit**

```bash
git add Server/Sources/MessageBridgeCore/API/APIResponses.swift Server/Sources/MessageBridgeCore/Messaging/MessageSenderProtocol.swift Server/Sources/MessageBridgeCore/Messaging/AppleScriptMessageSender.swift Server/Sources/MessageBridgeCore/API/Routes.swift Server/Tests/
git commit -m "feat(server): add replyToGuid to send message pipeline"
```

---

### Task 5: Server — AppleScript UI automation for sending replies

**Files:**
- Modify: `Server/Sources/MessageBridgeCore/Messaging/AppleScriptMessageSender.swift:9-89`
- Test: `Server/Tests/MessageBridgeCoreTests/Models/MessageReplyTests.swift` (extend)

**Step 1: Write the failing test**

Add to `MessageReplyTests.swift` (or create a new `AppleScriptReplyTests.swift`):

```swift
import XCTest
@testable import MessageBridgeCore

final class AppleScriptReplyTests: XCTestCase {
  let sender = AppleScriptMessageSender()

  func testBuildReplyAppleScript_containsReplyKeyword() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "Thanks!",
      replyToText: "Original message here",
      service: "iMessage"
    )
    // Reply script should reference the original message text to find it
    XCTAssertTrue(script.contains("Original message here"), "Script should reference original message")
    XCTAssertTrue(script.contains("Thanks!"), "Script should contain reply text")
  }

  func testBuildReplyAppleScript_escapesSpecialCharacters() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "He said \"hello\"",
      replyToText: "What did he say?",
      service: "iMessage"
    )
    XCTAssertTrue(script.contains("\\\""), "Script should escape quotes")
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd Server && swift test --filter AppleScriptReplyTests`
Expected: FAIL — `buildReplyAppleScript` doesn't exist

**Step 3: Implement `buildReplyAppleScript` and update `sendMessage`**

In `AppleScriptMessageSender.swift`, add a new method and update `sendMessage`:

```swift
public func sendMessage(to recipient: String, text: String, service: String?, replyToGuid: String? = nil) async throws -> SendResult {
  guard !recipient.isEmpty else {
    throw MessageSendError.invalidRecipient(recipient)
  }
  guard !text.isEmpty else {
    throw MessageSendError.emptyMessage
  }

  let serviceType = service ?? "iMessage"

  // For now, reply-to sends as a regular message
  // UI automation for reply requires the original message text and a visible Messages.app window
  // This will be enhanced with actual reply UI automation in a future iteration
  let script = buildAppleScript(recipient: recipient, text: text, service: serviceType)

  try await executeAppleScript(script)

  return SendResult(
    success: true,
    recipient: recipient,
    service: serviceType,
    timestamp: Date()
  )
}

/// Build AppleScript that replies to a specific message via UI automation.
/// This uses System Events to right-click the target message and select Reply.
func buildReplyAppleScript(
  recipient: String, text: String, replyToText: String, service: String
) -> String {
  let escapedText = text
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
  let escapedOriginal = replyToText
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")

  // UI automation approach:
  // 1. Find the conversation in Messages.app
  // 2. Find the message bubble containing the original text
  // 3. Right-click it and select "Reply"
  // 4. Type the reply text and press Return
  return """
    tell application "Messages"
      activate
    end tell

    delay 0.3

    tell application "System Events"
      tell process "Messages"
        -- Find the message containing the original text in the transcript
        set transcriptGroup to missing value
        try
          set transcriptGroup to group 1 of splitter group 1 of window 1
        end try

        if transcriptGroup is missing value then
          error "Could not find Messages transcript"
        end if

        -- Search through the accessibility tree for the message text
        set foundElement to missing value
        set allElements to entire contents of transcriptGroup
        repeat with elem in allElements
          try
            if description of elem contains "\(escapedOriginal)" then
              set foundElement to elem
              exit repeat
            end if
          end try
          try
            if value of elem contains "\(escapedOriginal)" then
              set foundElement to elem
              exit repeat
            end if
          end try
        end repeat

        if foundElement is missing value then
          error "Could not find message: \(escapedOriginal)"
        end if

        -- Right-click the found message element
        perform action "AXShowMenu" of foundElement

        delay 0.3

        -- Click "Reply" in context menu
        set replyItem to missing value
        repeat with menuItem in menu items of menu 1 of foundElement
          try
            if name of menuItem is "Reply" then
              set replyItem to menuItem
              exit repeat
            end if
          end try
        end repeat

        if replyItem is missing value then
          error "Could not find Reply menu item"
        end if

        click replyItem

        delay 0.3

        -- Type the reply text
        keystroke "\(escapedText)"

        delay 0.1

        -- Press Return to send
        keystroke return
      end tell
    end tell
    """
}
```

**Important note:** The UI automation approach is experimental and may need adjustment based on macOS 26.2's actual accessibility tree. The `buildReplyAppleScript` method is internal (not private) so it's testable without executing. The actual `sendMessage` currently falls back to regular send even when `replyToGuid` is provided — full UI-automation integration requires testing against the live Messages.app UI tree and will be wired up after verifying the script works via `osascript`.

**Step 4: Run test to verify it passes**

Run: `cd Server && swift test --filter AppleScriptReplyTests`
Expected: PASS

**Step 5: Run full server tests**

Run: `cd Server && swift test`
Expected: All pass

**Step 6: Commit**

```bash
git add Server/Sources/MessageBridgeCore/Messaging/AppleScriptMessageSender.swift Server/Tests/
git commit -m "feat(server): add reply AppleScript builder (UI automation scaffold)"
```

---

### Task 6: Client — Add reply fields to client Message model

**Files:**
- Modify: `Client/Sources/MessageBridgeClientCore/Models/Models.swift:247-315`
- Test: `Client/Tests/MessageBridgeClientCoreTests/Models/MessageReplyClientTests.swift` (new)

**Step 1: Write the failing test**

Create `Client/Tests/MessageBridgeClientCoreTests/Models/MessageReplyClientTests.swift`:

```swift
import XCTest
@testable import MessageBridgeClientCore

final class MessageReplyClientTests: XCTestCase {

  func testMessage_replyFieldsDefaultToNil() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Hello", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1"
    )
    XCTAssertNil(msg.replyToGuid)
    XCTAssertNil(msg.threadOriginatorGuid)
  }

  func testMessage_replyFieldsStoreValues() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Hello", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1",
      replyToGuid: "reply-guid",
      threadOriginatorGuid: "thread-guid"
    )
    XCTAssertEqual(msg.replyToGuid, "reply-guid")
    XCTAssertEqual(msg.threadOriginatorGuid, "thread-guid")
  }

  func testMessage_decodesReplyFieldsFromJSON() throws {
    let json = """
    {
      "id": 1, "guid": "msg-001", "text": "Reply text",
      "date": 0, "isFromMe": false, "handleId": 1,
      "conversationId": "chat1", "attachments": [],
      "replyToGuid": "original-guid",
      "threadOriginatorGuid": "thread-root-guid"
    }
    """.data(using: .utf8)!

    let msg = try JSONDecoder().decode(Message.self, from: json)
    XCTAssertEqual(msg.replyToGuid, "original-guid")
    XCTAssertEqual(msg.threadOriginatorGuid, "thread-root-guid")
  }

  func testMessage_decodesWithoutReplyFields() throws {
    let json = """
    {
      "id": 1, "guid": "msg-001", "text": "Plain text",
      "date": 0, "isFromMe": false, "handleId": 1,
      "conversationId": "chat1", "attachments": []
    }
    """.data(using: .utf8)!

    let msg = try JSONDecoder().decode(Message.self, from: json)
    XCTAssertNil(msg.replyToGuid)
    XCTAssertNil(msg.threadOriginatorGuid)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd Client && swift test --filter MessageReplyClientTests 2>&1 | head -20`
Expected: FAIL — `replyToGuid` parameter doesn't exist

**Step 3: Write minimal implementation**

In `Client/Sources/MessageBridgeClientCore/Models/Models.swift`:

Add fields to `Message` struct (after line 262, `linkPreview`):
```swift
public let replyToGuid: String?
public let threadOriginatorGuid: String?
```

Update `CodingKeys` (line 264-268) to include:
```swift
case replyToGuid, threadOriginatorGuid
```

Update the `init` (line 270-296) to accept:
```swift
replyToGuid: String? = nil,
threadOriginatorGuid: String? = nil
```

Update the `init(from decoder:)` (line 298-315) to decode:
```swift
replyToGuid = try container.decodeIfPresent(String.self, forKey: .replyToGuid)
threadOriginatorGuid = try container.decodeIfPresent(String.self, forKey: .threadOriginatorGuid)
```

**Step 4: Run test to verify it passes**

Run: `cd Client && swift test --filter MessageReplyClientTests`
Expected: PASS

**Step 5: Run full client tests**

Run: `cd Client && swift test`
Expected: All pass

**Step 6: Commit**

```bash
git add Client/Sources/MessageBridgeClientCore/Models/Models.swift Client/Tests/MessageBridgeClientCoreTests/Models/MessageReplyClientTests.swift
git commit -m "feat(client): add replyToGuid and threadOriginatorGuid to Message model"
```

---

### Task 7: Client — Create ReplyPreviewDecorator

**Files:**
- Create: `Client/Sources/MessageBridgeClientCore/Decorators/ReplyPreviewDecorator.swift`
- Create: `Client/Sources/MessageBridgeClient/Views/ReplyQuoteBar.swift`
- Test: `Client/Tests/MessageBridgeClientCoreTests/Decorators/ReplyPreviewDecoratorTests.swift` (new)
- Modify: `Client/Sources/MessageBridgeClient/App/MessageBridgeApp.swift:82-84` (register decorator)

**Step 1: Write the failing test**

Create `Client/Tests/MessageBridgeClientCoreTests/Decorators/ReplyPreviewDecoratorTests.swift`:

```swift
import XCTest
@testable import MessageBridgeClientCore

final class ReplyPreviewDecoratorTests: XCTestCase {
  let decorator = ReplyPreviewDecorator()
  let context = DecoratorContext(isLastSentMessage: false, isLastMessage: false, conversationId: "chat1")

  func testId() {
    XCTAssertEqual(decorator.id, "replyPreview")
  }

  func testPosition_isTopLeading() {
    XCTAssertEqual(decorator.position, .topLeading)
  }

  func testShouldDecorate_returnsTrueWhenReplyToGuidPresent() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Reply", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1",
      replyToGuid: "original-guid"
    )
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_returnsFalseWhenNoReplyFields() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Normal", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1"
    )
    XCTAssertFalse(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_returnsTrueWhenThreadOriginatorGuidPresent() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Reply", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1",
      threadOriginatorGuid: "thread-guid"
    )
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd Client && swift test --filter ReplyPreviewDecoratorTests 2>&1 | head -20`
Expected: FAIL — `ReplyPreviewDecorator` doesn't exist

**Step 3: Create the decorator**

Create `Client/Sources/MessageBridgeClientCore/Decorators/ReplyPreviewDecorator.swift`:

```swift
import SwiftUI

/// Decorator that shows a reply quote bar above the message bubble
/// when the message is a reply to another message.
public struct ReplyPreviewDecorator: BubbleDecorator {
  public let id = "replyPreview"
  public let position = DecoratorPosition.topLeading

  public init() {}

  public func shouldDecorate(_ message: Message, context: DecoratorContext) -> Bool {
    message.replyToGuid != nil || message.threadOriginatorGuid != nil
  }

  @MainActor
  public func decorate(_ message: Message, context: DecoratorContext) -> AnyView {
    AnyView(
      ReplyQuoteBar(message: message)
        .padding(.bottom, 2)
    )
  }
}
```

Create `Client/Sources/MessageBridgeClient/Views/ReplyQuoteBar.swift`:

```swift
import MessageBridgeClientCore
import SwiftUI

/// Compact quote bar showing the original message context for replies.
/// Displays sender name and truncated text with a colored left border.
struct ReplyQuoteBar: View {
  let message: Message

  var body: some View {
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 1)
        .fill(message.isFromMe ? Color.gray : Color.accentColor)
        .frame(width: 2)

      VStack(alignment: .leading, spacing: 1) {
        Text("Reply")
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .frame(maxWidth: 200, alignment: .leading)
  }
}
```

**Step 4: Register the decorator**

In `Client/Sources/MessageBridgeClient/App/MessageBridgeApp.swift`, add after line 84:

```swift
DecoratorRegistry.shared.register(ReplyPreviewDecorator())
```

**Step 5: Run test to verify it passes**

Run: `cd Client && swift test --filter ReplyPreviewDecoratorTests`
Expected: PASS

**Step 6: Render the `.topLeading` decorators in MessageBubble**

In `Client/Sources/MessageBridgeClient/Views/MessageThreadView.swift`, the `MessageBubble` view currently renders `.topTrailing` decorators inside the ZStack (lines 237-243) but does NOT render `.topLeading`. Add a block for `.topLeading` decorators ABOVE the bubble content VStack (before line 216):

Inside the existing ZStack (line 215), add `.topLeading` rendering. The cleanest approach: wrap the bubble content in a VStack and place topLeading decorators above it:

```swift
// Replace the ZStack content block (lines 215-244) with:
VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 0) {
  // Top-leading decorators (reply preview)
  ForEach(
    DecoratorRegistry.shared.decorators(
      for: message, at: .topLeading, context: decoratorContext), id: \.id
  ) { decorator in
    decorator.decorate(message, context: decoratorContext)
  }

  // Existing ZStack for bubble + topTrailing decorators
  ZStack(alignment: message.isFromMe ? .topLeading : .topTrailing) {
    // ... existing bubble content ...
  }
}
```

**Step 7: Build and run full tests**

Run: `cd Client && swift test`
Expected: All pass

**Step 8: Commit**

```bash
git add Client/Sources/MessageBridgeClientCore/Decorators/ReplyPreviewDecorator.swift Client/Sources/MessageBridgeClient/Views/ReplyQuoteBar.swift Client/Tests/MessageBridgeClientCoreTests/Decorators/ReplyPreviewDecoratorTests.swift Client/Sources/MessageBridgeClient/App/MessageBridgeApp.swift Client/Sources/MessageBridgeClient/Views/MessageThreadView.swift
git commit -m "feat(client): add ReplyPreviewDecorator and ReplyQuoteBar for reply display"
```

---

### Task 8: Client — Update BridgeServiceProtocol and BridgeConnection for reply send

**Files:**
- Modify: `Client/Sources/MessageBridgeClientCore/Services/BridgeConnection.swift:66-83, 351-386`

**Step 1: Update `BridgeServiceProtocol` (line 71)**

Change the sendMessage signature:

```swift
func sendMessage(text: String, to recipient: String, replyToGuid: String?) async throws
```

**Step 2: Update `BridgeConnection.sendMessage` (lines 351-386)**

Add `replyToGuid` parameter and include it in the request body:

```swift
public func sendMessage(text: String, to recipient: String, replyToGuid: String? = nil) async throws {
  guard let serverURL, let apiKey else {
    throw BridgeError.notConnected
  }

  var request = URLRequest(url: serverURL.appendingPathComponent("send"))
  request.httpMethod = "POST"
  request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
  request.addValue("application/json", forHTTPHeaderField: "Content-Type")

  var body: [String: String] = ["to": recipient, "text": text]
  if let replyToGuid {
    body["replyToGuid"] = replyToGuid
  }

  // ... rest of encryption and send logic unchanged ...
}
```

**Step 3: Update any mock implementations**

Search for mock implementations of `BridgeServiceProtocol` in client tests and update their `sendMessage` signatures.

**Step 4: Build and test**

Run: `cd Client && swift test`
Expected: All pass

**Step 5: Commit**

```bash
git add Client/Sources/MessageBridgeClientCore/Services/BridgeConnection.swift Client/Tests/
git commit -m "feat(client): add replyToGuid to sendMessage in BridgeConnection"
```

---

### Task 9: Client — Update MessagesViewModel.sendMessage

**Files:**
- Modify: `Client/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift:476-521`

**Step 1: Add `replyToGuid` parameter**

Update the method signature and pass through:

```swift
public func sendMessage(_ text: String, toConversation conversation: Conversation, replyToGuid: String? = nil) async {
  // ... existing recipient logic ...

  // Optimistic UI update
  let optimisticMessage = Message(
    id: Int64.random(in: Int64.min..<0),
    guid: UUID().uuidString,
    text: text,
    date: Date(),
    isFromMe: true,
    handleId: nil,
    conversationId: conversationId,
    replyToGuid: replyToGuid
  )
  messages[conversationId, default: []].insert(optimisticMessage, at: 0)

  do {
    try await bridgeService.sendMessage(text: text, to: recipient, replyToGuid: replyToGuid)
    // ... rest unchanged ...
  }
}
```

**Step 2: Build and test**

Run: `cd Client && swift test`
Expected: All pass

**Step 3: Commit**

```bash
git add Client/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift
git commit -m "feat(client): pass replyToGuid through MessagesViewModel.sendMessage"
```

---

### Task 10: Client — Wire up ReplyAction, composer banner, and send flow

**Files:**
- Modify: `Client/Sources/MessageBridgeClientCore/Actions/ReplyAction.swift:1-19`
- Modify: `Client/Sources/MessageBridgeClient/Views/MessageThreadView.swift:1-154`
- Modify: `Client/Sources/MessageBridgeClient/Views/Composer/ComposerView.swift:1-44`
- Create: `Client/Sources/MessageBridgeClient/Views/Composer/ReplyBanner.swift`

**Step 1: Update ReplyAction to post notification**

Replace the stub in `ReplyAction.swift`:

```swift
import AppKit

/// Begins a reply to a message by posting a notification.
public struct ReplyAction: MessageAction {
  public let id = "reply"
  public let title = "Reply"
  public let icon = "arrowshape.turn.up.left"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    true
  }

  @MainActor
  public func perform(on message: Message) async {
    NotificationCenter.default.post(
      name: .beginReply,
      object: nil,
      userInfo: ["message": message]
    )
  }
}
```

**Step 2: Create ReplyBanner view**

Create `Client/Sources/MessageBridgeClient/Views/Composer/ReplyBanner.swift`:

```swift
import MessageBridgeClientCore
import SwiftUI

/// Banner shown above the composer when replying to a message.
struct ReplyBanner: View {
  let message: Message
  let onCancel: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 1)
        .fill(Color.accentColor)
        .frame(width: 2)

      VStack(alignment: .leading, spacing: 1) {
        Text(message.isFromMe ? "You" : "Reply")
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundStyle(.accentColor)

        if let text = message.text {
          Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      Button {
        onCancel()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
          .font(.body)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)
  }
}
```

**Step 3: Update ComposerView to accept optional reply banner**

In `ComposerView.swift`, add a `replyingTo` binding and show the banner:

```swift
struct ComposerView: View {
  @Binding var text: String
  let onSend: () -> Void
  @Binding var replyingTo: Message?

  var body: some View {
    VStack(spacing: 0) {
      if let replyMessage = replyingTo {
        ReplyBanner(message: replyMessage) {
          replyingTo = nil
        }
        Divider()
      }

      HStack(alignment: .bottom, spacing: 8) {
        ComposerToolbar(context: composerContext)

        ExpandingTextEditor(
          text: $text,
          onSubmit: handleSubmit
        )

        SendButton(enabled: canSend) {
          onSend()
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
  }

  // ... rest unchanged ...
}
```

**Step 4: Update MessageThreadView to manage reply state**

In `MessageThreadView.swift`, add state and wire everything together:

Add state (after line 13):
```swift
@State private var replyingTo: Message?
```

Update ComposerView call (lines 114-116):
```swift
ComposerView(text: $messageText, onSend: { sendMessage() }, replyingTo: $replyingTo)
```

Update `sendMessage()` (lines 148-154):
```swift
private func sendMessage() {
  guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
  let replyGuid = replyingTo?.guid
  Task {
    await viewModel.sendMessage(messageText, toConversation: conversation, replyToGuid: replyGuid)
    messageText = ""
    replyingTo = nil
  }
}
```

Add notification handler (after the `.onReceive` for tapbacks, around line 130):
```swift
.onReceive(NotificationCenter.default.publisher(for: .beginReply)) { notification in
  if let message = notification.userInfo?["message"] as? Message {
    replyingTo = message
  }
}
```

**Step 5: Build and test**

Run: `cd Client && swift test`
Expected: All pass

**Step 6: Commit**

```bash
git add Client/Sources/MessageBridgeClientCore/Actions/ReplyAction.swift Client/Sources/MessageBridgeClient/Views/Composer/ReplyBanner.swift Client/Sources/MessageBridgeClient/Views/Composer/ComposerView.swift Client/Sources/MessageBridgeClient/Views/MessageThreadView.swift
git commit -m "feat(client): wire up reply action, composer banner, and send flow"
```

---

### Task 11: Final integration — Build, test, verify

**Step 1: Run full server test suite**

Run: `cd Server && swift test`
Expected: All pass

**Step 2: Run full client test suite**

Run: `cd Client && swift test`
Expected: All pass

**Step 3: Build both projects**

Run: `cd Server && swift build && cd ../Client && swift build`
Expected: Both build successfully

**Step 4: Commit any remaining fixes**

If any tests failed, fix and commit.

**Step 5: Final commit**

```bash
git add -A
git commit -m "feat: reply-to-message feature — display and compose"
```
