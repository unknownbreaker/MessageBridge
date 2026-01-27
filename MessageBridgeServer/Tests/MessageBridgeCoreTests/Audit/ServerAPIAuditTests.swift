import XCTVapor
import XCTest

@testable import MessageBridgeCore

/// Blind audit tests for M1.1 (Basic Server) + M1.3 (Send Messages).
/// Written from spec.md acceptance criteria without reading implementation.
final class ServerAPIAuditTests: XCTestCase {

  // MARK: - M1.1: GET /conversations returns paginated list

  func testGetConversations_returnsOK() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

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

  func testConversations_withoutAPIKey_returns401() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configureRoutes(app, database: MockChatDatabase(), messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations") { res in
      XCTAssertEqual(res.status, .unauthorized)
    }
  }

  func testConversations_withInvalidAPIKey_returns401() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configureRoutes(app, database: MockChatDatabase(), messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations", headers: ["X-API-Key": "wrong-key"]) { res in
      XCTAssertEqual(res.status, .unauthorized)
    }
  }

  func testMessages_withoutAPIKey_returns401() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configureRoutes(app, database: MockChatDatabase(), messageSender: MockMessageSender(), apiKey: "test-key")

    try app.test(.GET, "conversations/c1/messages") { res in
      XCTAssertEqual(res.status, .unauthorized)
    }
  }

  // MARK: - M1.3: POST /send

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

// MARK: - Audit Findings
// Compiled: YES
// Tests passed: 8/8
// Failures: none
// Compilation errors: none
