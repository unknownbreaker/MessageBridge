import XCTVapor
import XCTest

@testable import MessageBridgeCore

/// Mock implementation of ChatDatabaseProtocol for testing
final class MockChatDatabase: ChatDatabaseProtocol, @unchecked Sendable {
  var conversationsToReturn: [Conversation] = []
  var messagesToReturn: [Message] = []
  var searchResultsToReturn: [Message] = []
  var shouldThrowError = false

  var fetchConversationsCalled = false
  var fetchMessagesCalled = false
  var searchMessagesCalled = false
  var lastSearchQuery: String?
  var lastConversationId: String?
  var lastLimit: Int?
  var lastOffset: Int?

  func fetchRecentConversations(limit: Int, offset: Int) async throws -> [Conversation] {
    fetchConversationsCalled = true
    lastLimit = limit
    lastOffset = offset
    if shouldThrowError {
      throw DatabaseError.queryFailed
    }
    return conversationsToReturn
  }

  func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message] {
    fetchMessagesCalled = true
    lastConversationId = conversationId
    lastLimit = limit
    lastOffset = offset
    if shouldThrowError {
      throw DatabaseError.queryFailed
    }
    return messagesToReturn
  }

  func searchMessages(query: String, limit: Int) async throws -> [Message] {
    searchMessagesCalled = true
    lastSearchQuery = query
    lastLimit = limit
    if shouldThrowError {
      throw DatabaseError.queryFailed
    }
    return searchResultsToReturn
  }

  var attachmentToReturn: (attachment: Attachment, filePath: String)?
  var fetchAttachmentCalled = false
  var lastAttachmentId: Int64?

  func fetchAttachment(id: Int64) async throws -> (attachment: Attachment, filePath: String)? {
    fetchAttachmentCalled = true
    lastAttachmentId = id
    if shouldThrowError {
      throw DatabaseError.queryFailed
    }
    return attachmentToReturn
  }

  var markAsReadCalled = false
  var lastMarkedConversationId: String?

  func markConversationAsRead(conversationId: String) async throws {
    markAsReadCalled = true
    lastMarkedConversationId = conversationId
    if shouldThrowError {
      throw DatabaseError.queryFailed
    }
  }

  var newMessagesToReturn: [(message: Message, conversationId: String, senderAddress: String?)] = []

  func fetchMessagesNewerThan(id: Int64, limit: Int) throws -> [(
    message: Message, conversationId: String, senderAddress: String?
  )] {
    if shouldThrowError {
      throw DatabaseError.queryFailed
    }
    return newMessagesToReturn
  }
}

enum DatabaseError: Error {
  case queryFailed
}

/// Mock implementation of MessageSenderProtocol for testing
final class MockMessageSender: MessageSenderProtocol, @unchecked Sendable {
  var sendMessageCalled = false
  var lastRecipient: String?
  var lastText: String?
  var lastService: String?
  var shouldThrowError = false
  var errorToThrow: MessageSendError = .scriptExecutionFailed("Test error")
  var resultToReturn: SendResult?

  func sendMessage(to recipient: String, text: String, service: String?) async throws -> SendResult
  {
    sendMessageCalled = true
    lastRecipient = recipient
    lastText = text
    lastService = service

    if shouldThrowError {
      throw errorToThrow
    }

    return resultToReturn
      ?? SendResult(
        success: true,
        recipient: recipient,
        service: service ?? "iMessage",
        timestamp: Date()
      )
  }
}

final class APITests: XCTestCase {

  // MARK: - Health Endpoint Tests

  func testHealth_returnsOKStatus() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(.GET, "health") { response in
      XCTAssertEqual(response.status, .ok)

      let health = try response.content.decode(HealthResponse.self)
      XCTAssertEqual(health.status, "ok")
    }
  }

  // MARK: - API Key Authentication Tests

  func testConversations_withoutAPIKey_returnsUnauthorized() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(.GET, "conversations") { response in
      XCTAssertEqual(response.status, .unauthorized)
    }
  }

  func testConversations_withInvalidAPIKey_returnsUnauthorized() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(.GET, "conversations", headers: ["X-API-Key": "wrong-key"]) { response in
      XCTAssertEqual(response.status, .unauthorized)
    }
  }

  func testConversations_withValidAPIKey_returnsOK() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(.GET, "conversations", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .ok)
    }
  }

  // MARK: - GET /conversations Tests

  func testConversations_returnsConversationsList() throws {
    let mockDb = MockChatDatabase()
    mockDb.conversationsToReturn = [
      createTestConversation(id: "chat1", displayName: "John Doe"),
      createTestConversation(id: "chat2", displayName: "Jane Smith"),
    ]

    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "conversations", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .ok)

      let result = try response.content.decode(ConversationsResponse.self)
      XCTAssertEqual(result.conversations.count, 2)
      XCTAssertEqual(result.conversations[0].id, "chat1")
      XCTAssertEqual(result.conversations[1].id, "chat2")
    }

    XCTAssertTrue(mockDb.fetchConversationsCalled)
  }

  func testConversations_withPagination_passesLimitAndOffset() throws {
    let mockDb = MockChatDatabase()
    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "conversations?limit=10&offset=20", headers: ["X-API-Key": "test-api-key"]) {
      response in
      XCTAssertEqual(response.status, .ok)
    }

    XCTAssertEqual(mockDb.lastLimit, 10)
    XCTAssertEqual(mockDb.lastOffset, 20)
  }

  func testConversations_withDatabaseError_returnsInternalError() throws {
    let mockDb = MockChatDatabase()
    mockDb.shouldThrowError = true

    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "conversations", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .internalServerError)
    }
  }

  // MARK: - GET /conversations/:id/messages Tests

  func testMessages_returnsMessagesList() throws {
    let mockDb = MockChatDatabase()
    mockDb.messagesToReturn = [
      createTestMessage(id: 1, text: "Hello"),
      createTestMessage(id: 2, text: "World"),
    ]

    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "conversations/chat123/messages", headers: ["X-API-Key": "test-api-key"]) {
      response in
      XCTAssertEqual(response.status, .ok)

      let result = try response.content.decode(MessagesResponse.self)
      XCTAssertEqual(result.messages.count, 2)
      XCTAssertEqual(result.messages[0].text, "Hello")
      XCTAssertEqual(result.messages[1].text, "World")
    }

    XCTAssertEqual(mockDb.lastConversationId, "chat123")
  }

  func testMessages_withPagination_passesLimitAndOffset() throws {
    let mockDb = MockChatDatabase()
    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(
      .GET, "conversations/chat123/messages?limit=25&offset=50",
      headers: ["X-API-Key": "test-api-key"]
    ) { response in
      XCTAssertEqual(response.status, .ok)
    }

    XCTAssertEqual(mockDb.lastLimit, 25)
    XCTAssertEqual(mockDb.lastOffset, 50)
  }

  // MARK: - GET /search Tests

  func testSearch_withQuery_returnsMatchingMessages() throws {
    let mockDb = MockChatDatabase()
    mockDb.searchResultsToReturn = [
      createTestMessage(id: 1, text: "Hello world"),
      createTestMessage(id: 2, text: "Hello there"),
    ]

    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "search?q=hello", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .ok)

      let result = try response.content.decode(SearchResponse.self)
      XCTAssertEqual(result.messages.count, 2)
    }

    XCTAssertEqual(mockDb.lastSearchQuery, "hello")
  }

  func testSearch_withoutQuery_returnsBadRequest() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(.GET, "search", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .badRequest)
    }
  }

  func testSearch_withEmptyQuery_returnsBadRequest() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(.GET, "search?q=", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .badRequest)
    }
  }

  // MARK: - POST /send Tests

  func testSend_withoutAPIKey_returnsUnauthorized() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(
      .POST, "send",
      beforeRequest: { req in
        try req.content.encode(SendMessageRequest(to: "+15551234567", text: "Hello"))
      }
    ) { response in
      XCTAssertEqual(response.status, .unauthorized)
    }
  }

  func testSend_withValidRequest_sendsMessage() throws {
    let mockSender = MockMessageSender()
    let app = try createTestApp(messageSender: mockSender)
    defer { app.shutdown() }

    try app.test(
      .POST, "send", headers: ["X-API-Key": "test-api-key"],
      beforeRequest: { req in
        try req.content.encode(SendMessageRequest(to: "+15551234567", text: "Hello from test"))
      }
    ) { response in
      XCTAssertEqual(response.status, .ok)

      let result = try response.content.decode(SendResponse.self)
      XCTAssertTrue(result.success)
      XCTAssertEqual(result.recipient, "+15551234567")
    }

    XCTAssertTrue(mockSender.sendMessageCalled)
    XCTAssertEqual(mockSender.lastRecipient, "+15551234567")
    XCTAssertEqual(mockSender.lastText, "Hello from test")
  }

  func testSend_withService_passesServiceToSender() throws {
    let mockSender = MockMessageSender()
    let app = try createTestApp(messageSender: mockSender)
    defer { app.shutdown() }

    try app.test(
      .POST, "send", headers: ["X-API-Key": "test-api-key"],
      beforeRequest: { req in
        try req.content.encode(
          SendMessageRequest(to: "+15551234567", text: "Hello", service: "SMS"))
      }
    ) { response in
      XCTAssertEqual(response.status, .ok)
    }

    XCTAssertEqual(mockSender.lastService, "SMS")
  }

  func testSend_withMissingRecipient_returnsBadRequest() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(
      .POST, "send", headers: ["X-API-Key": "test-api-key"],
      beforeRequest: { req in
        try req.content.encode(["text": "Hello"])
      }
    ) { response in
      XCTAssertEqual(response.status, .badRequest)
    }
  }

  func testSend_withMissingText_returnsBadRequest() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(
      .POST, "send", headers: ["X-API-Key": "test-api-key"],
      beforeRequest: { req in
        try req.content.encode(["to": "+15551234567"])
      }
    ) { response in
      XCTAssertEqual(response.status, .badRequest)
    }
  }

  func testSend_withEmptyText_returnsBadRequest() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(
      .POST, "send", headers: ["X-API-Key": "test-api-key"],
      beforeRequest: { req in
        try req.content.encode(SendMessageRequest(to: "+15551234567", text: ""))
      }
    ) { response in
      XCTAssertEqual(response.status, .badRequest)
    }
  }

  func testSend_whenSenderFails_returnsInternalError() throws {
    let mockSender = MockMessageSender()
    mockSender.shouldThrowError = true
    mockSender.errorToThrow = .scriptExecutionFailed("AppleScript failed")

    let app = try createTestApp(messageSender: mockSender)
    defer { app.shutdown() }

    try app.test(
      .POST, "send", headers: ["X-API-Key": "test-api-key"],
      beforeRequest: { req in
        try req.content.encode(SendMessageRequest(to: "+15551234567", text: "Hello"))
      }
    ) { response in
      XCTAssertEqual(response.status, .internalServerError)
    }
  }

  // MARK: - Attachments Endpoint Tests

  func testAttachments_withValidId_returnsFile() throws {
    let mockDb = MockChatDatabase()
    let testAttachment = Attachment(
      id: 123,
      guid: "test-guid",
      filename: "test.txt",
      mimeType: "text/plain",
      uti: nil,
      size: 11,
      isOutgoing: false,
      isSticker: false
    )

    // Create a temporary test file
    let tempDir = FileManager.default.temporaryDirectory
    let testFilePath = tempDir.appendingPathComponent("test-attachment.txt").path
    try "Hello World".write(toFile: testFilePath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: testFilePath) }

    mockDb.attachmentToReturn = (testAttachment, testFilePath)

    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "attachments/123", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .ok)
      XCTAssertEqual(response.headers.contentType?.type, "text")
      XCTAssertEqual(response.headers.contentType?.subType, "plain")
    }

    XCTAssertTrue(mockDb.fetchAttachmentCalled)
    XCTAssertEqual(mockDb.lastAttachmentId, 123)
  }

  func testAttachments_withInvalidId_returnsBadRequest() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(.GET, "attachments/invalid", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .badRequest)
    }
  }

  func testAttachments_withNonexistentId_returnsNotFound() throws {
    let mockDb = MockChatDatabase()
    mockDb.attachmentToReturn = nil  // Attachment not found

    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "attachments/999", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .notFound)
    }
  }

  func testAttachments_withMissingFile_returnsNotFound() throws {
    let mockDb = MockChatDatabase()
    let testAttachment = Attachment(
      id: 123,
      guid: "test-guid",
      filename: "missing.txt",
      mimeType: "text/plain",
      uti: nil,
      size: 100,
      isOutgoing: false,
      isSticker: false
    )
    mockDb.attachmentToReturn = (testAttachment, "/nonexistent/path/to/file.txt")

    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "attachments/123", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .notFound)
    }
  }

  func testAttachments_withoutAPIKey_returnsUnauthorized() throws {
    let app = try createTestApp()
    defer { app.shutdown() }

    try app.test(.GET, "attachments/123") { response in
      XCTAssertEqual(response.status, .unauthorized)
    }
  }

  func testAttachments_withImageMimeType_setsCorrectContentType() throws {
    let mockDb = MockChatDatabase()
    let testAttachment = Attachment(
      id: 456,
      guid: "img-guid",
      filename: "photo.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 1000,
      isOutgoing: false,
      isSticker: false
    )

    // Create a temporary test file (just use text for testing, content doesn't matter)
    let tempDir = FileManager.default.temporaryDirectory
    let testFilePath = tempDir.appendingPathComponent("test-image.jpg").path
    try "fake image data".write(toFile: testFilePath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: testFilePath) }

    mockDb.attachmentToReturn = (testAttachment, testFilePath)

    let app = try createTestApp(database: mockDb)
    defer { app.shutdown() }

    try app.test(.GET, "attachments/456", headers: ["X-API-Key": "test-api-key"]) { response in
      XCTAssertEqual(response.status, .ok)
      XCTAssertEqual(response.headers.contentType?.type, "image")
      XCTAssertEqual(response.headers.contentType?.subType, "jpeg")
    }
  }

  // MARK: - Helper Methods

  private func createTestApp(
    database: ChatDatabaseProtocol? = nil, messageSender: MessageSenderProtocol? = nil
  ) throws -> Application {
    let app = Application(.testing)

    let db = database ?? MockChatDatabase()
    let sender = messageSender ?? MockMessageSender()
    try configureRoutes(app, database: db, messageSender: sender, apiKey: "test-api-key")

    return app
  }

  private func createTestConversation(id: String, displayName: String) -> Conversation {
    Conversation(
      id: id,
      guid: "guid-\(id)",
      displayName: displayName,
      participants: [],
      lastMessage: nil,
      isGroup: false
    )
  }

  private func createTestMessage(id: Int64, text: String) -> Message {
    Message(
      id: id,
      guid: "msg-\(id)",
      text: text,
      date: Date(),
      isFromMe: false,
      handleId: nil,
      conversationId: "chat1"
    )
  }
}
