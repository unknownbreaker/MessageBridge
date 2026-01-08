import XCTest
import XCTVapor
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
}

enum DatabaseError: Error {
    case queryFailed
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
            createTestConversation(id: "chat2", displayName: "Jane Smith")
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

        try app.test(.GET, "conversations?limit=10&offset=20", headers: ["X-API-Key": "test-api-key"]) { response in
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
            createTestMessage(id: 2, text: "World")
        ]

        let app = try createTestApp(database: mockDb)
        defer { app.shutdown() }

        try app.test(.GET, "conversations/chat123/messages", headers: ["X-API-Key": "test-api-key"]) { response in
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

        try app.test(.GET, "conversations/chat123/messages?limit=25&offset=50", headers: ["X-API-Key": "test-api-key"]) { response in
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
            createTestMessage(id: 2, text: "Hello there")
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

    // MARK: - Helper Methods

    private func createTestApp(database: ChatDatabaseProtocol? = nil) throws -> Application {
        let app = Application(.testing)

        let db = database ?? MockChatDatabase()
        try configureRoutes(app, database: db, apiKey: "test-api-key")

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
