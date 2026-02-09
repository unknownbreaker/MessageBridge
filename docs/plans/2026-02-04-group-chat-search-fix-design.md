# Group Chat Search Fix: Poll-Until-Ready with Client Feedback

**Date:** 2026-02-04
**Status:** Approved

## Problem

When marking group chats as read, `openGroupChatViaUISearch` in `ChatDatabase.swift` uses a hardcoded 1-second delay before pressing arrow-down to select search results. When Messages.app takes longer to populate results, the keystrokes go nowhere and the sync fails silently.

## Solution

Replace the fixed delay with a **poll-until-ready** pattern that detects when search results actually appear, with retry and fallback logic, plus client-side feedback for failures.

## Implementation

### 1. Server: Poll for Search Results

**Detection strategy:** Use `entire contents of front window` to scan for a `static text` element with `description = "Conversations"` — this section header appears when search results load.

**Updated `openGroupChatViaUISearch` AppleScript:**

```applescript
tell application "Messages" to activate
delay 0.3

tell application "System Events"
    tell process "Messages"
        -- Open search
        keystroke "f" using command down
        delay 0.2

        -- Type search string
        keystroke "{searchString}"

        -- Poll for results (up to 3 seconds)
        set resultsFound to false
        repeat 20 times
            delay 0.15
            try
                set allElements to entire contents of front window
                repeat with elem in allElements
                    if class of elem is static text then
                        if description of elem is "Conversations" then
                            set resultsFound to true
                            exit repeat
                        end if
                    end if
                end repeat
            end try
            if resultsFound then exit repeat
        end repeat

        if resultsFound then
            -- Select first result
            key code 125  -- arrow down
            delay 0.1
            key code 36   -- return
            delay 0.2
            key code 53   -- escape
            return "success"
        else
            return "no_results"
        end if
    end tell
end tell
```

### 2. Server: Retry and Fallback Logic

**Swift wrapper in `ChatDatabase.swift`:**

```swift
enum SyncResult {
    case success
    case failed(reason: String)
}

private func openGroupChatViaUISearch(chatInfo: GroupChatInfo) async -> SyncResult {
    guard let searchString = chatInfo.displayName, !searchString.isEmpty else {
        // No display name - fall back to URL scheme immediately
        return await fallbackToURLScheme(chatInfo: chatInfo)
    }

    // Attempt 1
    let result1 = await executeSearchScript(searchString: searchString)
    if result1 == "success" { return .success }

    // Clear search and retry once
    await clearSearchField()
    let result2 = await executeSearchScript(searchString: searchString)
    if result2 == "success" { return .success }

    // Fallback to URL scheme
    return await fallbackToURLScheme(chatInfo: chatInfo)
}

private func fallbackToURLScheme(chatInfo: GroupChatInfo) async -> SyncResult {
    let addressList = chatInfo.handles.joined(separator: ",")
    guard let url = URL(string: "messages://open?addresses=\(addressList)") else {
        return .failed(reason: "Could not build fallback URL")
    }

    await MainActor.run {
        NSWorkspace.shared.open(url)
    }

    return .failed(reason: "Fell back to URL scheme - may have opened wrong chat")
}

private func clearSearchField() async {
    let script = """
        tell application "System Events"
            tell process "Messages"
                key code 53  -- escape to close search
                delay 0.2
            end tell
        end tell
        """
    // Execute script...
}
```

### 3. Server: WebSocket Events for Sync Status

**New event types:**

```swift
enum WebSocketEventType: String, Codable {
    // ... existing types ...
    case syncWarning = "sync_warning"
    case syncWarningCleared = "sync_warning_cleared"
}

struct SyncWarningEvent: Codable {
    let conversationId: String
    let message: String
}
```

**Emit warning when sync fails:**

```swift
// In markAsRead or after syncReadStateWithMessagesApp
if case .failed(let reason) = syncResult {
    await webSocketManager.broadcast(
        event: .syncWarning,
        data: SyncWarningEvent(
            conversationId: conversationId,
            message: "Read status could not be synced to Messages.app"
        )
    )
}
```

**Emit clear when sync succeeds:**

```swift
if case .success = syncResult {
    await webSocketManager.broadcast(
        event: .syncWarningCleared,
        data: ["conversationId": conversationId]
    )
}
```

### 4. Client: Warning Banner Component

**New file:** `SyncWarningBanner.swift`

```swift
import SwiftUI

struct SyncWarningBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .foregroundStyle(.yellow)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.1))
    }
}
```

### 5. Client: Integration in MessageThreadView

**ViewModel changes:**

```swift
class MessageThreadViewModel: ObservableObject {
    @Published var syncWarning: String?

    func dismissSyncWarning() {
        syncWarning = nil
    }

    // Handle WebSocket events
    func handleSyncWarning(conversationId: String, message: String) {
        if conversationId == self.conversationId {
            syncWarning = message
        }
    }

    func handleSyncWarningCleared(conversationId: String) {
        if conversationId == self.conversationId {
            syncWarning = nil
        }
    }
}
```

**View changes:**

```swift
struct MessageThreadView: View {
    @StateObject var viewModel: MessageThreadViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let warning = viewModel.syncWarning {
                SyncWarningBanner(
                    message: warning,
                    onDismiss: { viewModel.dismissSyncWarning() }
                )
            }

            // Existing message list...
            MessageList(...)
        }
    }
}
```

## UI Mockup

```
┌─────────────────────────────────────────────────┐
│ ⚠️ Read status could not be synced           ✕ │  ← yellow warning banner
├─────────────────────────────────────────────────┤
│                                                 │
│  [Message bubbles as normal...]                 │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Files to Modify

**Server:**
- `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift`
  - Update `openGroupChatViaUISearch` with poll-until-ready logic
  - Add retry and fallback logic
  - Return `SyncResult` instead of void
- `MessageBridgeServer/Sources/MessageBridgeCore/WebSocket/WebSocketManager.swift`
  - Add `sync_warning` and `sync_warning_cleared` event types

**Client:**
- `MessageBridgeClient/Sources/MessageBridgeClient/Views/Messages/SyncWarningBanner.swift` (new)
- `MessageBridgeClient/Sources/MessageBridgeClient/Views/Messages/MessageThreadView.swift`
  - Add warning banner at top
- `MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessageThreadViewModel.swift`
  - Add `syncWarning` state
  - Handle WebSocket events
- `MessageBridgeClient/Sources/MessageBridgeClientCore/Services/WebSocketClient.swift`
  - Handle new event types

## Testing

1. **Manual test:** Search for a group chat with duplicate participants, verify results are detected before proceeding
2. **Slow results test:** Add artificial delay, verify polling waits appropriately
3. **No results test:** Search for nonexistent chat, verify retry then fallback occurs
4. **Client feedback test:** Force sync failure, verify warning appears in client and can be dismissed
5. **Auto-clear test:** After failed sync, trigger successful sync, verify warning clears

## Cleanup

Delete diagnostic scripts after implementation:
- `Scripts/dump-messages-ui.scpt`
- `Scripts/dump-search-ui.scpt`
- `Scripts/dump-all-ui.scpt`
- `Scripts/dump-popover.scpt`
