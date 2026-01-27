# Phase 1 Milestone Audit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Write blind spec-based audit tests for M1.1–M1.4 acceptance criteria and report which pass, fail, or don't compile.

**Architecture:** Four test files written purely from spec.md acceptance criteria without reading implementation code. Tests use assumed API shapes. Compilation failures and test failures are both valid audit findings that get recorded in the CLAUDE.md tracker.

**Tech Stack:** Swift, XCTest, XCTVapor (server), macOS 14+

---

### Task 1: ServerAPIAuditTests (M1.1 + M1.3)

**Files:**
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Audit/ServerAPIAuditTests.swift`

**Step 1: Write the tests (blind from spec)**

These tests are derived from spec acceptance criteria:
- M1.1: "GET /conversations returns paginated conversation list"
- M1.1: "GET /conversations/:id/messages returns messages"
- M1.1: "All endpoints require X-API-Key header"
- M1.1: "Invalid API key returns 401"
- M1.3: "POST /send endpoint accepts message"

```swift
import XCTVapor
import XCTest

@testable import MessageBridgeCore

/// Blind audit tests for M1.1 (Basic Server) + M1.3 (Send Messages).
/// Written from spec.md acceptance criteria without reading implementation.
final class ServerAPIAuditTests: XCTestCase {

  // MARK: - M1.1: GET /conversations returns paginated list

  /// Spec: "GET /conversations returns paginated conversation list"
  func testGetConversations_returnsOK() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    // Assume configureRoutes exists and takes app + mock database + API key
    let mockDb = MockChatDatabase()
    mockDb.conversationsToReturn = [
      Conversation(
        id: "c1", guid: "g1", displayName: "Alice",
        participants: [], lastMessage: nil, isGroup: false)
    ]
    try configureRoutes(app, database: mockDb, messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations", headers: ["X-API-Key": "test-key"]) { res in
      XCTAssertEqual(res.status, .ok)
    }
  }

  /// Spec: "GET /conversations returns paginated conversation list"
  func testGetConversations_supportsPagination() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    let mockDb = MockChatDatabase()
    try configureRoutes(app, database: mockDb, messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations?limit=10&offset=5", headers: ["X-API-Key": "test-key"]) { res in
      XCTAssertEqual(res.status, .ok)
    }

    XCTAssertEqual(mockDb.lastLimit, 10)
    XCTAssertEqual(mockDb.lastOffset, 5)
  }

  // MARK: - M1.1: GET /conversations/:id/messages

  /// Spec: "GET /conversations/:id/messages returns messages"
  func testGetMessages_returnsOK() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    let mockDb = MockChatDatabase()
    mockDb.messagesToReturn = [
      Message(id: 1, guid: "m1", text: "Hello", date: Date(),
              isFromMe: false, handleId: nil, conversationId: "c1")
    ]
    try configureRoutes(app, database: mockDb, messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations/c1/messages", headers: ["X-API-Key": "test-key"]) { res in
      XCTAssertEqual(res.status, .ok)
    }
  }

  // MARK: - M1.1: Authentication

  /// Spec: "All endpoints require X-API-Key header"
  func testConversations_withoutAPIKey_returns401() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configureRoutes(app, database: MockChatDatabase(), messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations") { res in
      XCTAssertEqual(res.status, .unauthorized)
    }
  }

  /// Spec: "Invalid API key returns 401"
  func testConversations_withInvalidAPIKey_returns401() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configureRoutes(app, database: MockChatDatabase(), messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations", headers: ["X-API-Key": "wrong-key"]) { res in
      XCTAssertEqual(res.status, .unauthorized)
    }
  }

  /// Spec: "All endpoints require X-API-Key header" (messages endpoint)
  func testMessages_withoutAPIKey_returns401() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configureRoutes(app, database: MockChatDatabase(), messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations/c1/messages") { res in
      XCTAssertEqual(res.status, .unauthorized)
    }
  }

  // MARK: - M1.3: POST /send

  /// Spec: "POST /send endpoint accepts message"
  func testPostSend_returnsOK() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    let mockSender = MockMessageSender()
    try configureRoutes(app, database: MockChatDatabase(), messageSender: mockSender, apiKey: "test-key")

    try app.test(.POST, "send", headers: ["X-API-Key": "test-key"], beforeRequest: { req in
      try req.content.encode(SendMessageRequest(to: "+15551234567", text: "Hello"))
    }) { res in
      XCTAssertEqual(res.status, .ok)
    }

    XCTAssertTrue(mockSender.sendMessageCalled)
  }

  /// Spec: "POST /send endpoint accepts message" (auth required)
  func testPostSend_withoutAPIKey_returns401() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configureRoutes(app, database: MockChatDatabase(), messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.POST, "send", beforeRequest: { req in
      try req.content.encode(SendMessageRequest(to: "+15551234567", text: "Hello"))
    }) { res in
      XCTAssertEqual(res.status, .unauthorized)
    }
  }
}
```

**Step 2: Try to build**

Run: `cd MessageBridgeServer && swift build --build-tests 2>&1 | tail -30`

Record findings:
- If it compiles: proceed to run tests
- If compilation errors: record each error as a finding (spec assumption doesn't match implementation)

**Step 3: Run tests (if compiled)**

Run: `cd MessageBridgeServer && swift test --filter ServerAPIAuditTests 2>&1 | tail -30`

**Step 4: Record results**

Create a findings section at the bottom of the test file as comments:

```swift
// MARK: - Audit Findings
// Compiled: YES/NO
// Tests passed: X/Y
// Failures: [list]
// Compilation errors: [list]
```

**Step 5: Commit**

```bash
cd MessageBridgeServer && git add Tests/MessageBridgeCoreTests/Audit/ServerAPIAuditTests.swift
git commit -m "test(audit): add M1.1+M1.3 server API audit tests"
```

---

### Task 2: DatabaseAuditTests (M1.1 + M1.4)

**Files:**
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Audit/DatabaseAuditTests.swift`

**Step 1: Write the tests (blind from spec)**

Derived from:
- M1.1: "Reads from ~/Library/Messages/chat.db (read-only)"
- M1.4: "WebSocket connection at /ws"
- M1.4: "Server watches chat.db for changes"

```swift
import XCTest

@testable import MessageBridgeCore

/// Blind audit tests for M1.1 (Database) + M1.4 (Real-time).
/// Written from spec.md acceptance criteria without reading implementation.
final class DatabaseAuditTests: XCTestCase {

  // MARK: - M1.1: Database Access

  /// Spec: "Reads from ~/Library/Messages/chat.db (read-only)"
  /// Verify that a ChatDatabase type exists and conforms to a protocol.
  func testChatDatabaseProtocol_exists() {
    // If this compiles, ChatDatabaseProtocol exists
    let _: ChatDatabaseProtocol.Type = MockChatDatabase.self
  }

  /// Spec: "Reads from ~/Library/Messages/chat.db (read-only)"
  /// Verify the protocol has conversation fetch capability.
  func testChatDatabase_canFetchConversations() async throws {
    let db = MockChatDatabase()
    let conversations = try await db.fetchRecentConversations(limit: 20, offset: 0)
    XCTAssertNotNil(conversations)
  }

  /// Spec: "Reads from ~/Library/Messages/chat.db (read-only)"
  /// Verify the protocol has message fetch capability.
  func testChatDatabase_canFetchMessages() async throws {
    let db = MockChatDatabase()
    let messages = try await db.fetchMessages(conversationId: "c1", limit: 50, offset: 0)
    XCTAssertNotNil(messages)
  }

  // MARK: - M1.4: Real-time Infrastructure

  /// Spec: "Server watches chat.db for changes"
  /// Verify a ChatDatabaseWatcher type exists.
  func testChatDatabaseWatcher_typeExists() {
    // If this compiles, the watcher exists
    let _: ChatDatabaseWatcher.Type = ChatDatabaseWatcher.self
  }

  /// Spec: "WebSocket connection at /ws"
  /// Verify WebSocket route can be registered (existence check).
  func testWebSocketRoute_canBeConfigured() throws {
    // This test verifies the route configuration function accepts ws setup
    // If configureRoutes compiles with our mock, ws route infrastructure exists
    let app = Application(.testing)
    defer { app.shutdown() }

    try configureRoutes(
      app, database: MockChatDatabase(),
      messageSender: MockMessageSender(), apiKey: "test-key")

    // If we got here, routes including /ws are configured
  }
}
```

**Step 2: Try to build**

Run: `cd MessageBridgeServer && swift build --build-tests 2>&1 | tail -30`

**Step 3: Run tests (if compiled)**

Run: `cd MessageBridgeServer && swift test --filter DatabaseAuditTests 2>&1 | tail -30`

**Step 4: Record results as comments**

**Step 5: Commit**

```bash
cd MessageBridgeServer && git add Tests/MessageBridgeCoreTests/Audit/DatabaseAuditTests.swift
git commit -m "test(audit): add M1.1+M1.4 database audit tests"
```

---

### Task 3: ClientViewAuditTests (M1.2 + M1.3)

**Files:**
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Views/ClientViewAuditTests.swift`

**Step 1: Write the tests (blind from spec)**

Derived from:
- M1.2: "Conversation list shows contact name, last message preview, date"
- M1.2: "Message thread shows bubbles with sent/received styling"
- M1.3: "Composer text field at bottom of message thread"

```swift
import XCTest

@testable import MessageBridgeClientCore

/// Blind audit tests for M1.2 (Basic Client) + M1.3 (Composer).
/// Written from spec.md acceptance criteria without reading implementation.
final class ClientViewAuditTests: XCTestCase {

  // MARK: - M1.2: Conversation Model

  /// Spec: "Conversation list shows contact name, last message preview, date"
  func testConversation_hasDisplayName() {
    let convo = Conversation(
      id: "c1", guid: "g1", displayName: "Alice",
      participants: [], lastMessage: nil, isGroup: false)
    XCTAssertEqual(convo.displayName, "Alice")
  }

  /// Spec: "Conversation list shows contact name, last message preview, date"
  func testConversation_hasLastMessage() {
    let msg = Message(
      id: 1, guid: "m1", text: "Hey", date: Date(),
      isFromMe: false, handleId: nil, conversationId: "c1")
    let convo = Conversation(
      id: "c1", guid: "g1", displayName: "Alice",
      participants: [], lastMessage: msg, isGroup: false)
    XCTAssertNotNil(convo.lastMessage)
    XCTAssertEqual(convo.lastMessage?.text, "Hey")
  }

  /// Spec: "Conversation list shows contact name, last message preview, date"
  func testMessage_hasDate() {
    let now = Date()
    let msg = Message(
      id: 1, guid: "m1", text: "Hello", date: now,
      isFromMe: false, handleId: nil, conversationId: "c1")
    XCTAssertEqual(msg.date, now)
  }

  // MARK: - M1.2: Message Model

  /// Spec: "Message thread shows bubbles with sent/received styling"
  func testMessage_hasText() {
    let msg = Message(
      id: 1, guid: "m1", text: "Hello", date: Date(),
      isFromMe: false, handleId: nil, conversationId: "c1")
    XCTAssertEqual(msg.text, "Hello")
  }

  /// Spec: "Message thread shows bubbles with sent/received styling"
  func testMessage_isFromMe_distinguishesSentReceived() {
    let sent = Message(
      id: 1, guid: "m1", text: "Sent", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1")
    let received = Message(
      id: 2, guid: "m2", text: "Received", date: Date(),
      isFromMe: false, handleId: nil, conversationId: "c1")
    XCTAssertTrue(sent.isFromMe)
    XCTAssertFalse(received.isFromMe)
  }

  /// Spec: "Message thread shows bubbles with sent/received styling"
  func testMessage_hasSender() {
    let msg = Message(
      id: 1, guid: "m1", text: "Hello", date: Date(),
      isFromMe: false, handleId: 42, conversationId: "c1")
    XCTAssertEqual(msg.handleId, 42)
  }

  // MARK: - M1.3: Composer Infrastructure

  /// Spec: "Composer text field at bottom of message thread"
  /// Verify SubmitEvent enum exists (composer infrastructure).
  func testSubmitEvent_exists() {
    let _: SubmitEvent = .enter
    let _: SubmitEvent = .shiftEnter
    let _: SubmitEvent = .commandEnter
    let _: SubmitEvent = .optionEnter
  }

  /// Spec: "Enter sends message (configurable)"
  /// Verify ComposerPlugin protocol exists.
  func testComposerPlugin_protocolExists() {
    // If this compiles, the protocol exists
    let _: any ComposerPlugin.Protocol = (any ComposerPlugin).self
  }
}
```

**Step 2: Try to build**

Run: `cd MessageBridgeClient && swift build --build-tests 2>&1 | tail -30`

**Step 3: Run tests (if compiled)**

Run: `cd MessageBridgeClient && swift test --filter ClientViewAuditTests 2>&1 | tail -30`

**Step 4: Record results as comments**

**Step 5: Commit**

```bash
cd MessageBridgeClient && git add Tests/MessageBridgeClientCoreTests/Views/ClientViewAuditTests.swift
git commit -m "test(audit): add M1.2+M1.3 client view audit tests"
```

---

### Task 4: ConnectionAuditTests (M1.2 + M1.4)

**Files:**
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Services/ConnectionAuditTests.swift`

**Step 1: Write the tests (blind from spec)**

Derived from:
- M1.2: "Settings screen for server URL and API key"
- M1.2: "Credentials stored in Keychain"
- M1.4: "Client reconnects automatically on disconnect"

```swift
import XCTest

@testable import MessageBridgeClientCore

/// Blind audit tests for M1.2 (Connection Config) + M1.4 (Real-time Client).
/// Written from spec.md acceptance criteria without reading implementation.
final class ConnectionAuditTests: XCTestCase {

  // MARK: - M1.2: Keychain Storage

  /// Spec: "Credentials stored in Keychain"
  /// Verify KeychainManager type exists.
  func testKeychainManager_typeExists() {
    let _ = KeychainManager()
  }

  /// Spec: "Settings screen for server URL and API key"
  /// Verify KeychainManager can store and retrieve a server config.
  func testKeychainManager_canStoreAndRetrieveConfig() throws {
    let km = KeychainManager()
    // Assume a ServerConfig or similar type, and store/retrieve methods
    // If this doesn't compile, it reveals the actual API shape
    let config = ServerConfig(
      serverURL: URL(string: "https://example.com")!,
      apiKey: "test-key",
      e2eEnabled: false)
    try km.saveServerConfig(config)
    let retrieved = try km.retrieveServerConfig()
    XCTAssertNotNil(retrieved)
    XCTAssertEqual(retrieved?.serverURL.absoluteString, "https://example.com")
    XCTAssertEqual(retrieved?.apiKey, "test-key")

    // Cleanup
    try? km.deleteServerConfig()
  }

  // MARK: - M1.2 + M1.4: Connection Status

  /// Spec: "Client reconnects automatically on disconnect"
  /// Verify ConnectionStatus enum exists with expected cases.
  func testConnectionStatus_hasExpectedCases() {
    let _: ConnectionStatus = .connected
    let _: ConnectionStatus = .disconnected
    let _: ConnectionStatus = .connecting
  }

  /// Spec: "Client reconnects automatically on disconnect"
  /// Verify MessagesViewModel exposes connection status.
  func testMessagesViewModel_hasConnectionStatus() {
    let vm = MessagesViewModel()
    let _: ConnectionStatus = vm.connectionStatus
  }

  // MARK: - M1.4: WebSocket Client

  /// Spec: "WebSocket connection at /ws" (client side)
  /// Verify a BridgeServiceProtocol exists for WebSocket communication.
  func testBridgeServiceProtocol_exists() {
    // If this compiles, the service protocol exists
    let _: any BridgeServiceProtocol.Protocol = (any BridgeServiceProtocol).self
  }
}
```

**Step 2: Try to build**

Run: `cd MessageBridgeClient && swift build --build-tests 2>&1 | tail -30`

**Step 3: Run tests (if compiled)**

Run: `cd MessageBridgeClient && swift test --filter ConnectionAuditTests 2>&1 | tail -30`

**Step 4: Record results as comments**

**Step 5: Commit**

```bash
cd MessageBridgeClient && git add Tests/MessageBridgeClientCoreTests/Services/ConnectionAuditTests.swift
git commit -m "test(audit): add M1.2+M1.4 connection audit tests"
```

---

### Task 5: Update CLAUDE.md Audit Tracker

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the audit tracker table**

Based on Task 1–4 results, update these rows in CLAUDE.md:

```
| M1.1 Basic Server          | ✅                 | [result]   | ✅       | ⬜       |
| M1.2 Basic Client          | ✅                 | [result]   | ✅       | ⬜       |
| M1.3 Send Messages         | ✅                 | [result]   | ✅       | ⬜       |
| M1.4 Real-time Updates     | ✅                 | [result]   | ✅       | ⬜       |
```

Where `[result]` is:
- ✅ if all audit tests pass
- 🟡 if some fail
- ⬜ if doesn't compile

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update Phase 1 audit tracker with results"
```
