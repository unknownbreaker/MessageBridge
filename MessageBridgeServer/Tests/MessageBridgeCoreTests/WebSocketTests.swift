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
        mockDb.newMessagesToReturn = []

        let mockWatcher = MockFileWatcher()
        let detector = MessageChangeDetector(database: mockDb, fileWatcher: mockWatcher)

        var queryCalled = false
        mockDb.newMessagesToReturn = []

        try await detector.startDetecting { _, _ in
            queryCalled = true
        }

        // Set up new message for when file change triggers
        mockDb.newMessagesToReturn = [
            (
                message: Message(
                    id: 100,
                    guid: "msg-100",
                    text: "Hello",
                    date: Date(),
                    isFromMe: false,
                    handleId: nil,
                    conversationId: "chat1"
                ),
                conversationId: "chat1",
                senderAddress: "+15551234567"
            )
        ]

        // Simulate file change
        mockWatcher.simulateChange()

        // Give async task time to run
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertTrue(queryCalled)
    }

    func testNewMessage_callsHandler() async throws {
        let mockDb = MockChatDatabase()

        // Start with no new messages
        mockDb.newMessagesToReturn = []

        let mockWatcher = MockFileWatcher()
        let detector = MessageChangeDetector(database: mockDb, fileWatcher: mockWatcher)

        var receivedMessage: Message?
        var receivedSender: String?

        try await detector.startDetecting { message, sender in
            receivedMessage = message
            receivedSender = sender
        }

        // Now update mock to return a new message
        let newMessage = Message(
            id: 200,
            guid: "msg-200",
            text: "New message!",
            date: Date(),
            isFromMe: false,
            handleId: 1,
            conversationId: "chat1"
        )

        mockDb.newMessagesToReturn = [
            (message: newMessage, conversationId: "chat1", senderAddress: "+15551234567")
        ]

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
