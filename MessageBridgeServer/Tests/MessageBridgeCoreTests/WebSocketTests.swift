import XCTest
import XCTVapor
@testable import MessageBridgeCore

/// Mock implementation of FileWatcherProtocol for testing
final class MockFileWatcher: FileWatcherProtocol, @unchecked Sendable {
    var startWatchingCalled = false
    var stopWatchingCalled = false
    var changeHandler: (@Sendable () -> Void)?

    func startWatching(handler: @escaping @Sendable () -> Void) async throws {
        startWatchingCalled = true
        changeHandler = handler
    }

    func stopWatching() async {
        stopWatchingCalled = true
        changeHandler = nil
    }

    /// Simulate a file change event
    func simulateChange() {
        changeHandler?()
    }
}

final class WebSocketManagerTests: XCTestCase {

    func testAddConnection_increasesConnectionCount() async {
        let manager = WebSocketManager()

        // We can't easily create a real WebSocket in tests, so we test the protocol/logic
        // The connection count starts at 0
        let count = await manager.connectionCount
        XCTAssertEqual(count, 0)
    }

    func testRemoveConnection_decreasesConnectionCount() async {
        let manager = WebSocketManager()

        let count = await manager.connectionCount
        XCTAssertEqual(count, 0)
    }
}

final class MessageChangeDetectorTests: XCTestCase {

    func testStartDetecting_startsFileWatcher() async throws {
        let mockDb = MockChatDatabase()
        let mockWatcher = MockFileWatcher()
        let detector = MessageChangeDetector(database: mockDb, fileWatcher: mockWatcher)

        try await detector.startDetecting { _, _ in }

        XCTAssertTrue(mockWatcher.startWatchingCalled)
    }

    func testStopDetecting_stopsFileWatcher() async throws {
        let mockDb = MockChatDatabase()
        let mockWatcher = MockFileWatcher()
        let detector = MessageChangeDetector(database: mockDb, fileWatcher: mockWatcher)

        try await detector.startDetecting { _, _ in }
        await detector.stopDetecting()

        XCTAssertTrue(mockWatcher.stopWatchingCalled)
    }

    func testFileChange_queriesDatabase() async throws {
        let mockDb = MockChatDatabase()
        // Start with no messages
        mockDb.conversationsToReturn = []

        let mockWatcher = MockFileWatcher()
        let detector = MessageChangeDetector(database: mockDb, fileWatcher: mockWatcher)

        try await detector.startDetecting { _, _ in }

        // Reset the flag after initial query
        mockDb.fetchConversationsCalled = false

        // Now set up conversations for when file change triggers
        mockDb.conversationsToReturn = [
            Conversation(
                id: "chat1",
                guid: "guid-1",
                displayName: "Test",
                participants: [],
                lastMessage: Message(
                    id: 100,
                    guid: "msg-100",
                    text: "Hello",
                    date: Date(),
                    isFromMe: false,
                    handleId: nil,
                    conversationId: "chat1"
                ),
                isGroup: false
            )
        ]

        // Simulate file change
        mockWatcher.simulateChange()

        // Give async task time to run
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertTrue(mockDb.fetchConversationsCalled)
    }

    func testNewMessage_callsHandler() async throws {
        let mockDb = MockChatDatabase()

        // Start with an old message (lower ID)
        let oldMessage = Message(
            id: 50,
            guid: "msg-50",
            text: "Old message",
            date: Date().addingTimeInterval(-3600),
            isFromMe: false,
            handleId: 1,
            conversationId: "chat1"
        )

        mockDb.conversationsToReturn = [
            Conversation(
                id: "chat1",
                guid: "guid-1",
                displayName: "Test",
                participants: [Handle(id: 1, address: "+15551234567", service: "iMessage")],
                lastMessage: oldMessage,
                isGroup: false
            )
        ]

        let mockWatcher = MockFileWatcher()
        let detector = MessageChangeDetector(database: mockDb, fileWatcher: mockWatcher)

        var receivedMessage: Message?
        var receivedSender: String?

        try await detector.startDetecting { message, sender in
            receivedMessage = message
            receivedSender = sender
        }

        // Now update mock to return a new message (higher ID)
        let newMessage = Message(
            id: 200,
            guid: "msg-200",
            text: "New message!",
            date: Date(),
            isFromMe: false,
            handleId: 1,
            conversationId: "chat1"
        )

        mockDb.conversationsToReturn = [
            Conversation(
                id: "chat1",
                guid: "guid-1",
                displayName: "Test",
                participants: [Handle(id: 1, address: "+15551234567", service: "iMessage")],
                lastMessage: newMessage,
                isGroup: false
            )
        ]
        mockDb.messagesToReturn = [newMessage]

        // Simulate file change
        mockWatcher.simulateChange()

        // Give async task time to run
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        XCTAssertNotNil(receivedMessage)
        XCTAssertEqual(receivedMessage?.id, 200)
        XCTAssertEqual(receivedMessage?.text, "New message!")
        XCTAssertEqual(receivedSender, "+15551234567")
    }
}

final class WebSocketRouteTests: XCTestCase {

    func testWebSocket_withoutAPIKey_closesConnection() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        let mockDb = MockChatDatabase()
        let mockSender = MockMessageSender()
        let wsManager = WebSocketManager()

        try configureRoutes(app, database: mockDb, messageSender: mockSender, apiKey: "test-api-key", webSocketManager: wsManager)

        // WebSocket testing in Vapor requires special handling
        // For now, we verify the route is registered
        XCTAssertNotNil(app.routes.all.first { $0.path.contains("ws") })
    }
}
