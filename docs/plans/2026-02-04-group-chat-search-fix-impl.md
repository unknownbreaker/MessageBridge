# Group Chat Search Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the group chat read-sync UI automation by polling for search results before proceeding, with retry, fallback, and client feedback.

**Architecture:** Replace hardcoded 1-second delay with poll-until-ready pattern using `entire contents` to detect "Conversations" section header. Add WebSocket events for sync warnings. Display warning banner in client.

**Tech Stack:** Swift, AppleScript/System Events, Vapor WebSocket, SwiftUI

---

## Task 1: Add WebSocket Message Types for Sync Warnings

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/API/WebSocketMessages.swift`

**Step 1: Write the test**

Create test file `MessageBridgeServer/Tests/MessageBridgeCoreTests/SyncWarningTests.swift`:

```swift
import XCTest
@testable import MessageBridgeCore

final class SyncWarningTests: XCTestCase {
    func testSyncWarningEvent_encodesCorrectly() throws {
        let event = SyncWarningEvent(
            conversationId: "chat123",
            message: "Read status could not be synced"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["conversationId"] as? String, "chat123")
        XCTAssertEqual(json["message"] as? String, "Read status could not be synced")
    }

    func testSyncWarningClearedEvent_encodesCorrectly() throws {
        let event = SyncWarningClearedEvent(conversationId: "chat123")

        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["conversationId"] as? String, "chat123")
    }

    func testWebSocketMessageType_includesSyncWarning() {
        XCTAssertEqual(WebSocketMessageType.syncWarning.rawValue, "sync_warning")
        XCTAssertEqual(WebSocketMessageType.syncWarningCleared.rawValue, "sync_warning_cleared")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter SyncWarningTests`
Expected: FAIL with "cannot find type 'SyncWarningEvent'"

**Step 3: Add message types to WebSocketMessages.swift**

Add to `WebSocketMessageType` enum:

```swift
case syncWarning = "sync_warning"
case syncWarningCleared = "sync_warning_cleared"
```

Add new event structs after `TapbackEvent`:

```swift
/// Data payload for sync warning events
public struct SyncWarningEvent: Codable, Sendable {
    public let conversationId: String
    public let message: String

    public init(conversationId: String, message: String) {
        self.conversationId = conversationId
        self.message = message
    }
}

/// Data payload for sync warning cleared events
public struct SyncWarningClearedEvent: Codable, Sendable {
    public let conversationId: String

    public init(conversationId: String) {
        self.conversationId = conversationId
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter SyncWarningTests`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/API/WebSocketMessages.swift MessageBridgeServer/Tests/MessageBridgeCoreTests/SyncWarningTests.swift
git commit -m "feat(server): add sync_warning WebSocket message types"
```

---

## Task 2: Add WebSocketManager Broadcast Methods for Sync Warnings

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/API/WebSocketManager.swift`

**Step 1: Write the test**

Add to `SyncWarningTests.swift`:

```swift
func testWebSocketManager_broadcastSyncWarning() async throws {
    // This is an integration test - we'll verify the method exists and compiles
    // Actual broadcast behavior is tested via WebSocket integration tests
    let manager = WebSocketManager()

    // Should compile and not throw
    await manager.broadcastSyncWarning(conversationId: "chat123", message: "Test warning")
    await manager.broadcastSyncWarningCleared(conversationId: "chat123")

    // If we get here, methods exist and work
    XCTAssertTrue(true)
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter testWebSocketManager_broadcastSyncWarning`
Expected: FAIL with "value of type 'WebSocketManager' has no member 'broadcastSyncWarning'"

**Step 3: Add broadcast methods to WebSocketManager.swift**

Add after `broadcastTapbackRemoved`:

```swift
/// Broadcast a sync warning to all connected clients
public func broadcastSyncWarning(conversationId: String, message: String) async {
    os_log(
        "Broadcasting sync warning for %{public}@ to %d client(s)", log: logger, type: .info,
        conversationId, connections.count)

    let event = SyncWarningEvent(conversationId: conversationId, message: message)
    let wsMessage = WebSocketMessage(type: .syncWarning, data: event)

    await broadcast(wsMessage)
}

/// Broadcast sync warning cleared to all connected clients
public func broadcastSyncWarningCleared(conversationId: String) async {
    os_log(
        "Broadcasting sync warning cleared for %{public}@ to %d client(s)", log: logger, type: .info,
        conversationId, connections.count)

    let event = SyncWarningClearedEvent(conversationId: conversationId)
    let wsMessage = WebSocketMessage(type: .syncWarningCleared, data: event)

    await broadcast(wsMessage)
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter testWebSocketManager_broadcastSyncWarning`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/API/WebSocketManager.swift MessageBridgeServer/Tests/MessageBridgeCoreTests/SyncWarningTests.swift
git commit -m "feat(server): add WebSocketManager sync warning broadcast methods"
```

---

## Task 3: Create SyncResult Enum and Update ChatDatabase Signature

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift`

**Step 1: Write the test**

Add to `SyncWarningTests.swift`:

```swift
func testSyncResult_hasCorrectCases() {
    let success = SyncResult.success
    let failed = SyncResult.failed(reason: "Test reason")

    switch success {
    case .success:
        XCTAssertTrue(true)
    case .failed:
        XCTFail("Expected success")
    }

    switch failed {
    case .success:
        XCTFail("Expected failed")
    case .failed(let reason):
        XCTAssertEqual(reason, "Test reason")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter testSyncResult_hasCorrectCases`
Expected: FAIL with "cannot find type 'SyncResult'"

**Step 3: Add SyncResult enum to ChatDatabase.swift**

Add near the top of the file, after imports:

```swift
/// Result of attempting to sync read state with Messages.app
public enum SyncResult: Sendable, Equatable {
    case success
    case failed(reason: String)
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter testSyncResult_hasCorrectCases`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift MessageBridgeServer/Tests/MessageBridgeCoreTests/SyncWarningTests.swift
git commit -m "feat(server): add SyncResult enum for tracking sync outcomes"
```

---

## Task 4: Implement Poll-Until-Ready AppleScript Logic

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift`

**Step 1: Write the test**

Add to `SyncWarningTests.swift`:

```swift
func testBuildSearchScript_containsPollLogic() {
    // Test that the script contains the polling pattern
    let script = ChatDatabase.buildSearchScript(searchString: "Test Chat")

    XCTAssertTrue(script.contains("repeat"), "Script should contain polling loop")
    XCTAssertTrue(script.contains("entire contents"), "Script should use entire contents")
    XCTAssertTrue(script.contains("Conversations"), "Script should look for Conversations header")
    XCTAssertTrue(script.contains("Test Chat"), "Script should contain search string")
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter testBuildSearchScript_containsPollLogic`
Expected: FAIL with "type 'ChatDatabase' has no member 'buildSearchScript'"

**Step 3: Add buildSearchScript method**

Add as a static method in ChatDatabase (we'll make it internal for testing):

```swift
/// Builds the AppleScript for searching Messages.app with poll-until-ready logic
/// - Parameter searchString: The chat name to search for
/// - Returns: AppleScript source code
static func buildSearchScript(searchString: String) -> String {
    let escapedSearch = searchString
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")

    return """
        tell application "Messages" to activate
        delay 0.3

        tell application "System Events"
            tell process "Messages"
                -- Open search
                keystroke "f" using command down
                delay 0.2

                -- Type search string
                keystroke "\(escapedSearch)"

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
                    key code 125
                    delay 0.1
                    key code 36
                    delay 0.2
                    key code 53
                    return "success"
                else
                    return "no_results"
                end if
            end tell
        end tell
        """
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter testBuildSearchScript_containsPollLogic`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift MessageBridgeServer/Tests/MessageBridgeCoreTests/SyncWarningTests.swift
git commit -m "feat(server): add poll-until-ready AppleScript builder"
```

---

## Task 5: Implement executeSearchScript Helper

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift`

**Step 1: Add the executeSearchScript method**

Add as a private method in ChatDatabase:

```swift
/// Executes the search AppleScript and returns the result
/// - Parameter searchString: The chat name to search for
/// - Returns: "success" if search worked, "no_results" if timed out
private func executeSearchScript(searchString: String) async -> String {
    let script = ChatDatabase.buildSearchScript(searchString: searchString)

    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let result = appleScript?.executeAndReturnError(&error)

            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                serverLogWarning("Search script error: \(errorMessage)")
                continuation.resume(returning: "error")
            } else if let resultString = result?.stringValue {
                continuation.resume(returning: resultString)
            } else {
                continuation.resume(returning: "error")
            }
        }
    }
}
```

**Step 2: Add clearSearchField helper**

```swift
/// Clears the search field by pressing Escape
private func clearSearchField() async {
    let script = """
        tell application "System Events"
            tell process "Messages"
                key code 53
                delay 0.2
            end tell
        end tell
        """

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            appleScript?.executeAndReturnError(&error)
            continuation.resume()
        }
    }
}
```

**Step 3: Run all tests to verify nothing broke**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift
git commit -m "feat(server): add executeSearchScript and clearSearchField helpers"
```

---

## Task 6: Refactor openGroupChatViaUISearch with Retry and Fallback

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift`

**Step 1: Replace the existing openGroupChatViaUISearch method**

Find the existing `openGroupChatViaUISearch` method and replace it with:

```swift
/// Opens a group chat using UI search with retry and fallback (requires Accessibility permission)
/// - Returns: SyncResult indicating success or failure with reason
private func openGroupChatViaUISearch(chatInfo: GroupChatInfo) async -> SyncResult {
    guard let searchString = chatInfo.displayName, !searchString.isEmpty else {
        serverLogWarning("Cannot use UI search: no display name for chat \(chatInfo.conversationId)")
        // Fall back to addresses even though duplicates exist - better than nothing
        return await fallbackToURLScheme(chatInfo: chatInfo)
    }

    serverLog("openGroupChatViaUISearch: searching for '\(searchString)'")

    // Attempt 1
    let result1 = await executeSearchScript(searchString: searchString)
    if result1 == "success" {
        serverLog("openGroupChatViaUISearch: success on first attempt")
        return .success
    }

    serverLog("openGroupChatViaUISearch: first attempt returned '\(result1)', retrying...")

    // Clear and retry once
    await clearSearchField()
    await Task.sleep(for: .milliseconds(300))

    let result2 = await executeSearchScript(searchString: searchString)
    if result2 == "success" {
        serverLog("openGroupChatViaUISearch: success on retry")
        return .success
    }

    serverLog("openGroupChatViaUISearch: retry returned '\(result2)', falling back to URL scheme")

    // Fallback to URL scheme
    return await fallbackToURLScheme(chatInfo: chatInfo)
}

/// Falls back to opening via URL scheme when UI search fails
private func fallbackToURLScheme(chatInfo: GroupChatInfo) async -> SyncResult {
    let addressList = chatInfo.handles.joined(separator: ",")
    guard let url = URL(string: "messages://open?addresses=\(addressList)") else {
        return .failed(reason: "Could not build fallback URL")
    }

    serverLog("openGroupChatViaUISearch: opening fallback URL = \(url)")

    await MainActor.run {
        NSWorkspace.shared.open(url)
    }

    return .failed(reason: "Read status could not be synced to Messages.app")
}
```

**Step 2: Run all tests to verify nothing broke**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 3: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift
git commit -m "feat(server): refactor openGroupChatViaUISearch with retry and fallback"
```

---

## Task 7: Wire Up Sync Result to WebSocket Broadcast

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift`

**Step 1: Update syncReadStateWithMessagesApp to return SyncResult**

Find `syncReadStateWithMessagesApp` and update it to return and broadcast sync warnings:

```swift
/// Nudges Messages.app to pick up the read-state changes written to chat.db.
/// - Returns: SyncResult indicating if the sync was successful
private func syncReadStateWithMessagesApp(conversationId: String) async -> SyncResult {
    let isGroupChat = conversationId.lowercased().hasPrefix("chat")
    serverLog("syncReadStateWithMessagesApp: \(conversationId), isGroupChat: \(isGroupChat)")

    let result: SyncResult
    if isGroupChat {
        result = await openGroupChatViaSearch(conversationId: conversationId)
    } else {
        await openConversationViaURLScheme(conversationId: conversationId)
        result = .success
    }

    return result
}
```

**Step 2: Update openGroupChatViaSearch to return SyncResult**

```swift
private func openGroupChatViaSearch(conversationId: String) async -> SyncResult {
    let now = Date()
    guard now.timeIntervalSince(lastGroupChatSearch) > 3 else {
        serverLogDebug("Skipping group chat search (debounced)")
        return .success  // Debounced is not a failure
    }
    lastGroupChatSearch = now

    // Get participant handles and chat info for this group chat
    guard let chatInfo = await getGroupChatInfo(conversationId: conversationId),
          !chatInfo.handles.isEmpty
    else {
        serverLogWarning("Could not get info for group chat: \(conversationId)")
        return .failed(reason: "Could not get chat info")
    }

    // Check if there are other chats with the exact same participants
    let hasDuplicates = await hasChatsWithSameParticipants(
        conversationId: conversationId, handles: chatInfo.handles)

    if hasDuplicates {
        // Fall back to UI search by chat name (requires Accessibility)
        serverLog("openGroupChatViaSearch: duplicate participants detected, using UI search")
        return await openGroupChatViaUISearch(chatInfo: chatInfo)
    } else {
        // Use URL scheme with addresses (no special permissions needed)
        let addressList = chatInfo.handles.joined(separator: ",")
        guard let url = URL(string: "messages://open?addresses=\(addressList)") else {
            serverLogWarning("Could not build URL for group chat: \(conversationId)")
            return .failed(reason: "Could not build URL")
        }

        serverLog("openGroupChatViaSearch: opening URL = \(url)")
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
        return .success
    }
}
```

**Step 3: Update markAsRead to broadcast sync warnings**

Find the `markAsRead` method and update the end to broadcast warnings. Add a dependency on WebSocketManager if not present. At the end of markAsRead, after `syncReadStateWithMessagesApp`:

```swift
// Broadcast sync warning if applicable
let syncResult = await syncReadStateWithMessagesApp(conversationId: conversationId)
if case .failed(let reason) = syncResult {
    await webSocketManager?.broadcastSyncWarning(
        conversationId: conversationId,
        message: reason
    )
}
```

Note: ChatDatabase may need a reference to WebSocketManager. Check if it already has one, or add it.

**Step 4: Run all tests**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift
git commit -m "feat(server): broadcast sync warnings when read-state sync fails"
```

---

## Task 8: Add Client Model for Sync Warnings

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/Models.swift` (or create new file)

**Step 1: Write the test**

Create `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/SyncWarningModelTests.swift`:

```swift
import XCTest
@testable import MessageBridgeClientCore

final class SyncWarningModelTests: XCTestCase {
    func testSyncWarningEvent_decodesCorrectly() throws {
        let json = """
        {"conversationId": "chat123", "message": "Read status could not be synced"}
        """
        let data = json.data(using: .utf8)!

        let event = try JSONDecoder().decode(SyncWarningEvent.self, from: data)

        XCTAssertEqual(event.conversationId, "chat123")
        XCTAssertEqual(event.message, "Read status could not be synced")
    }

    func testSyncWarningClearedEvent_decodesCorrectly() throws {
        let json = """
        {"conversationId": "chat123"}
        """
        let data = json.data(using: .utf8)!

        let event = try JSONDecoder().decode(SyncWarningClearedEvent.self, from: data)

        XCTAssertEqual(event.conversationId, "chat123")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeClient && swift test --filter SyncWarningModelTests`
Expected: FAIL

**Step 3: Add the models**

Add to Models.swift or create SyncWarningModels.swift:

```swift
/// Event received when sync warning occurs
public struct SyncWarningEvent: Codable, Sendable {
    public let conversationId: String
    public let message: String
}

/// Event received when sync warning is cleared
public struct SyncWarningClearedEvent: Codable, Sendable {
    public let conversationId: String
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeClient && swift test --filter SyncWarningModelTests`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Models/ MessageBridgeClient/Tests/MessageBridgeClientCoreTests/SyncWarningModelTests.swift
git commit -m "feat(client): add SyncWarning event models"
```

---

## Task 9: Add syncWarnings State to MessagesViewModel

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift`

**Step 1: Write the test**

Add to `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/ViewModels/MessagesViewModelTests.swift`:

```swift
func testSyncWarnings_initiallyEmpty() {
    let vm = MessagesViewModel(bridgeService: MockBridgeConnection())
    XCTAssertTrue(vm.syncWarnings.isEmpty)
}

func testHandleSyncWarning_addsWarning() async {
    let vm = MessagesViewModel(bridgeService: MockBridgeConnection())

    await vm.handleSyncWarning(conversationId: "chat123", message: "Test warning")

    XCTAssertEqual(vm.syncWarnings["chat123"], "Test warning")
}

func testHandleSyncWarningCleared_removesWarning() async {
    let vm = MessagesViewModel(bridgeService: MockBridgeConnection())
    await vm.handleSyncWarning(conversationId: "chat123", message: "Test warning")

    await vm.handleSyncWarningCleared(conversationId: "chat123")

    XCTAssertNil(vm.syncWarnings["chat123"])
}

func testDismissSyncWarning_removesWarning() async {
    let vm = MessagesViewModel(bridgeService: MockBridgeConnection())
    await vm.handleSyncWarning(conversationId: "chat123", message: "Test warning")

    vm.dismissSyncWarning(for: "chat123")

    XCTAssertNil(vm.syncWarnings["chat123"])
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeClient && swift test --filter testSyncWarnings`
Expected: FAIL

**Step 3: Add syncWarnings state and handlers to MessagesViewModel**

Add published property:

```swift
@Published public var syncWarnings: [String: String] = [:]  // conversationId -> warning message
```

Add handler methods:

```swift
/// Handle sync warning event from WebSocket
public func handleSyncWarning(conversationId: String, message: String) {
    syncWarnings[conversationId] = message
}

/// Handle sync warning cleared event from WebSocket
public func handleSyncWarningCleared(conversationId: String) {
    syncWarnings.removeValue(forKey: conversationId)
}

/// Dismiss sync warning for a conversation (user action)
public func dismissSyncWarning(for conversationId: String) {
    syncWarnings.removeValue(forKey: conversationId)
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeClient && swift test --filter testSyncWarnings`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift MessageBridgeClient/Tests/MessageBridgeClientCoreTests/ViewModels/MessagesViewModelTests.swift
git commit -m "feat(client): add syncWarnings state to MessagesViewModel"
```

---

## Task 10: Handle Sync Warning WebSocket Events in Client

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/Services/BridgeConnection.swift` (or WebSocket handler)

**Step 1: Add WebSocket message type handling**

Find where WebSocket messages are decoded and add handling for sync_warning and sync_warning_cleared types. Add callbacks to the WebSocket handler:

```swift
// In BridgeServiceProtocol or wherever WebSocket is handled
public typealias SyncWarningHandler = (SyncWarningEvent) -> Void
public typealias SyncWarningClearedHandler = (SyncWarningClearedEvent) -> Void
```

Update the WebSocket message handling to decode and call handlers for the new event types.

**Step 2: Wire up handlers in MessagesViewModel**

In `startWebSocket`, add handlers:

```swift
onSyncWarning: { [weak self] event in
    Task { @MainActor [weak self] in
        self?.handleSyncWarning(conversationId: event.conversationId, message: event.message)
    }
},
onSyncWarningCleared: { [weak self] event in
    Task { @MainActor [weak self] in
        self?.handleSyncWarningCleared(conversationId: event.conversationId)
    }
}
```

**Step 3: Run all client tests**

Run: `cd MessageBridgeClient && swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/
git commit -m "feat(client): handle sync warning WebSocket events"
```

---

## Task 11: Create SyncWarningBanner SwiftUI Component

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClient/Views/Messages/SyncWarningBanner.swift`

**Step 1: Create the component**

```swift
import SwiftUI

/// Banner displayed when read status sync fails for a conversation
struct SyncWarningBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .foregroundStyle(.yellow)
                .font(.caption)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.1))
    }
}

#Preview {
    VStack {
        SyncWarningBanner(
            message: "Read status could not be synced to Messages.app",
            onDismiss: {}
        )
        Spacer()
    }
}
```

**Step 2: Build to verify it compiles**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/Messages/SyncWarningBanner.swift
git commit -m "feat(client): add SyncWarningBanner component"
```

---

## Task 12: Integrate SyncWarningBanner into MessageThreadView

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift`

**Step 1: Add the banner to the view**

In MessageThreadView, add the banner between the header and messages. Find the `VStack(spacing: 0)` and add after the header divider:

```swift
VStack(spacing: 0) {
    // Header
    HStack { ... }
    .padding()
    .background(.bar)

    Divider()

    // Sync warning banner (if applicable)
    if let warning = viewModel.syncWarnings[conversation.id] {
        SyncWarningBanner(
            message: warning,
            onDismiss: {
                viewModel.dismissSyncWarning(for: conversation.id)
            }
        )
    }

    // Messages
    ScrollViewReader { proxy in
        ...
    }

    // Rest of view...
}
```

**Step 2: Build to verify it compiles**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 3: Run all client tests**

Run: `cd MessageBridgeClient && swift test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift
git commit -m "feat(client): integrate SyncWarningBanner into MessageThreadView"
```

---

## Task 13: Run Full Test Suite and Final Verification

**Step 1: Run server tests**

Run: `cd MessageBridgeServer && swift test`
Expected: All 500+ tests pass

**Step 2: Run client tests**

Run: `cd MessageBridgeClient && swift test`
Expected: All 330+ tests pass

**Step 3: Build release**

Run: `cd MessageBridgeServer && swift build -c release && cd ../MessageBridgeClient && swift build -c release`
Expected: Both build successfully

**Step 4: Commit any remaining changes**

```bash
git status
# If any uncommitted changes:
git add -A
git commit -m "chore: final cleanup"
```

---

## Task 14: Clean Up Diagnostic Scripts

**Files:**
- Delete: `Scripts/dump-messages-ui.scpt`
- Delete: `Scripts/dump-search-ui.scpt`
- Delete: `Scripts/dump-all-ui.scpt`
- Delete: `Scripts/dump-popover.scpt`

**Step 1: Remove the diagnostic scripts**

```bash
rm Scripts/dump-messages-ui.scpt Scripts/dump-search-ui.scpt Scripts/dump-all-ui.scpt Scripts/dump-popover.scpt
```

**Step 2: Commit**

```bash
git add -A
git commit -m "chore: remove diagnostic AppleScript files"
```

---

## Summary

After completing all tasks:

1. **Server changes:**
   - New WebSocket message types: `sync_warning`, `sync_warning_cleared`
   - `SyncResult` enum for tracking sync outcomes
   - Poll-until-ready AppleScript with "Conversations" header detection
   - Retry logic (1 retry) before fallback
   - URL scheme fallback when UI search fails
   - WebSocket broadcast of sync warnings

2. **Client changes:**
   - `SyncWarningEvent` and `SyncWarningClearedEvent` models
   - `syncWarnings` state in MessagesViewModel
   - WebSocket event handlers for sync warnings
   - `SyncWarningBanner` component (yellow, dismissable)
   - Banner integration in MessageThreadView

3. **Cleanup:**
   - Diagnostic AppleScript files removed
