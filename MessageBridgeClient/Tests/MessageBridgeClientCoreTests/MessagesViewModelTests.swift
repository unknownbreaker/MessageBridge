import XCTest
@testable import MessageBridgeClientCore

/// Mock implementation of BridgeServiceProtocol for testing
actor MockBridgeService: BridgeServiceProtocol {
    var connectCalled = false
    var fetchConversationsCalled = false
    var fetchMessagesCalled = false
    var sendMessageCalled = false

    var conversationsToReturn: [Conversation] = []
    var messagesToReturn: [Message] = []
    var messageToReturn: Message?
    var shouldThrowError = false

    func connect(to url: URL, apiKey: String) async throws {
        connectCalled = true
        if shouldThrowError {
            throw BridgeError.connectionFailed
        }
    }

    func fetchConversations(limit: Int, offset: Int) async throws -> [Conversation] {
        fetchConversationsCalled = true
        if shouldThrowError {
            throw BridgeError.requestFailed
        }
        return conversationsToReturn
    }

    func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message] {
        fetchMessagesCalled = true
        if shouldThrowError {
            throw BridgeError.requestFailed
        }
        return messagesToReturn
    }

    func sendMessage(text: String, to conversationId: String) async throws -> Message {
        sendMessageCalled = true
        if shouldThrowError {
            throw BridgeError.sendFailed
        }
        return messageToReturn!
    }
}

@MainActor
final class MessagesViewModelTests: XCTestCase {

    // MARK: - Connection Tests

    func testConnect_success_setsStatusToConnected() async {
        let mockService = MockBridgeService()
        let viewModel = MessagesViewModel(bridgeService: mockService)

        await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

        let connectCalled = await mockService.connectCalled
        XCTAssertTrue(connectCalled)
        XCTAssertEqual(viewModel.connectionStatus, .connected)
    }

    func testConnect_failure_setsStatusToDisconnected() async {
        let mockService = MockBridgeService()
        await mockService.setShouldThrowError(true)
        let viewModel = MessagesViewModel(bridgeService: mockService)

        await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
    }

    // MARK: - Load Conversations Tests

    func testLoadConversations_success_updatesConversations() async {
        let mockService = MockBridgeService()
        let testConversation = Conversation(
            id: "test-1",
            guid: "guid-1",
            displayName: "Test User",
            participants: [],
            lastMessage: nil,
            isGroup: false
        )
        await mockService.setConversationsToReturn([testConversation])

        let viewModel = MessagesViewModel(bridgeService: mockService)
        await viewModel.loadConversations()

        let fetchCalled = await mockService.fetchConversationsCalled
        XCTAssertTrue(fetchCalled)
        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(viewModel.conversations.first?.id, "test-1")
    }

    // MARK: - Send Message Tests

    func testSendMessage_success_addsMessageToList() async {
        let mockService = MockBridgeService()
        let sentMessage = Message(
            id: 100,
            guid: "sent-msg-guid",
            text: "Hello!",
            date: Date(),
            isFromMe: true,
            handleId: nil,
            conversationId: "chat-1"
        )
        await mockService.setMessageToReturn(sentMessage)

        let viewModel = MessagesViewModel(bridgeService: mockService)
        await viewModel.sendMessage("Hello!", to: "chat-1")

        let sendCalled = await mockService.sendMessageCalled
        XCTAssertTrue(sendCalled)
        XCTAssertEqual(viewModel.messages["chat-1"]?.first?.text, "Hello!")
    }
}

// MARK: - MockBridgeService Helpers

extension MockBridgeService {
    func setShouldThrowError(_ value: Bool) {
        shouldThrowError = value
    }

    func setConversationsToReturn(_ conversations: [Conversation]) {
        conversationsToReturn = conversations
    }

    func setMessageToReturn(_ message: Message) {
        messageToReturn = message
    }
}
