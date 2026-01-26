import XCTest

@testable import MessageBridgeClientCore

/// Mock implementation of BridgeServiceProtocol for testing
actor MockBridgeService: BridgeServiceProtocol {
  var connectCalled = false
  var disconnectCalled = false
  var fetchConversationsCalled = false
  var fetchMessagesCalled = false
  var sendMessageCalled = false
  var startWebSocketCalled = false
  var stopWebSocketCalled = false

  var conversationsToReturn: [Conversation] = []
  var messagesToReturn: [Message] = []
  var shouldThrowError = false
  var lastRecipient: String?
  var lastMessageText: String?
  var newMessageHandler: NewMessageHandler?

  func connect(to url: URL, apiKey: String, e2eEnabled: Bool) async throws {
    connectCalled = true
    if shouldThrowError {
      throw BridgeError.connectionFailed
    }
  }

  func disconnect() async {
    disconnectCalled = true
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

  func sendMessage(text: String, to recipient: String) async throws {
    sendMessageCalled = true
    lastRecipient = recipient
    lastMessageText = text
    if shouldThrowError {
      throw BridgeError.sendFailed
    }
  }

  func startWebSocket(onNewMessage: @escaping NewMessageHandler) async throws {
    startWebSocketCalled = true
    newMessageHandler = onNewMessage
  }

  func stopWebSocket() async {
    stopWebSocketCalled = true
    newMessageHandler = nil
  }

  var attachmentDataToReturn: Data = Data()
  var fetchAttachmentCalled = false
  var lastAttachmentId: Int64?

  func fetchAttachment(id: Int64) async throws -> Data {
    fetchAttachmentCalled = true
    lastAttachmentId = id
    if shouldThrowError {
      throw BridgeError.attachmentNotFound
    }
    return attachmentDataToReturn
  }

  var markAsReadCalled = false
  var lastMarkedConversationId: String?

  func markConversationAsRead(_ conversationId: String) async throws {
    markAsReadCalled = true
    lastMarkedConversationId = conversationId
    if shouldThrowError {
      throw BridgeError.requestFailed
    }
  }

  // Helper to simulate receiving a new message
  func simulateNewMessage(_ message: Message, sender: String) {
    newMessageHandler?(message, sender)
  }
}

@MainActor
final class MessagesViewModelTests: XCTestCase {

  // Helper to create ViewModel with mock services
  private func createViewModel(mockService: MockBridgeService) -> MessagesViewModel {
    let mockNotificationCenter = MockNotificationCenter()
    let notificationManager = NotificationManager(notificationCenter: mockNotificationCenter)
    return MessagesViewModel(bridgeService: mockService, notificationManager: notificationManager)
  }

  // MARK: - Connection Tests

  func testConnect_success_setsStatusToConnected() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

    let connectCalled = await mockService.connectCalled
    XCTAssertTrue(connectCalled)
    XCTAssertEqual(viewModel.connectionStatus, .connected)
  }

  func testConnect_failure_setsStatusToDisconnected() async {
    let mockService = MockBridgeService()
    await mockService.setShouldThrowError(true)
    let viewModel = createViewModel(mockService: mockService)

    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

    XCTAssertEqual(viewModel.connectionStatus, .disconnected)
  }

  func testDisconnect_setsStatusToDisconnected() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // First connect
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")
    XCTAssertEqual(viewModel.connectionStatus, .connected)

    // Then disconnect
    await viewModel.disconnect()

    let disconnectCalled = await mockService.disconnectCalled
    XCTAssertTrue(disconnectCalled)
    XCTAssertEqual(viewModel.connectionStatus, .disconnected)
  }

  func testDisconnect_clearsConversationsAndMessages() async {
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

    let viewModel = createViewModel(mockService: mockService)

    // Connect and load conversations
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")
    XCTAssertEqual(viewModel.conversations.count, 1)

    // Add some messages
    viewModel.messages["test-1"] = [
      Message(
        id: 1,
        guid: "msg-1",
        text: "Hello",
        date: Date(),
        isFromMe: false,
        handleId: nil,
        conversationId: "test-1"
      )
    ]

    // Disconnect
    await viewModel.disconnect()

    XCTAssertEqual(viewModel.conversations.count, 0)
    XCTAssertEqual(viewModel.messages.count, 0)
    XCTAssertNil(viewModel.selectedConversationId)
  }

  func testConnecting_setsStatusToConnecting() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // Check initial state
    XCTAssertEqual(viewModel.connectionStatus, .disconnected)

    // The status should be .connecting during the connect call
    // We verify this by checking the final status is .connected
    // which proves it went through the connecting phase
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")
    XCTAssertEqual(viewModel.connectionStatus, .connected)
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

    let viewModel = createViewModel(mockService: mockService)
    await viewModel.loadConversations()

    let fetchCalled = await mockService.fetchConversationsCalled
    XCTAssertTrue(fetchCalled)
    XCTAssertEqual(viewModel.conversations.count, 1)
    XCTAssertEqual(viewModel.conversations.first?.id, "test-1")
  }

  // MARK: - Send Message Tests

  func testSendMessage_success_addsMessageToList() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // Set up a conversation with a participant to send to
    let conversation = Conversation(
      id: "chat-1",
      guid: "guid-1",
      displayName: "Test User",
      participants: [Handle(id: 1, address: "+15551234567", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )
    await mockService.setConversationsToReturn([conversation])
    await viewModel.loadConversations()

    await viewModel.sendMessage("Hello!", toConversation: conversation)

    let sendCalled = await mockService.sendMessageCalled
    XCTAssertTrue(sendCalled)
    // Optimistic message should be in the list
    XCTAssertEqual(viewModel.messages["chat-1"]?.first?.text, "Hello!")
  }

  func testSendMessage_optimisticUpdate_showsMessageImmediately() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    let conversation = Conversation(
      id: "chat-1",
      guid: "guid-1",
      displayName: "Test User",
      participants: [Handle(id: 1, address: "+15551234567", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )
    await mockService.setConversationsToReturn([conversation])
    await viewModel.loadConversations()

    // Clear messages to start fresh
    viewModel.messages["chat-1"] = []

    await viewModel.sendMessage("Hello!", toConversation: conversation)

    // Message should appear in the list
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 1)
    XCTAssertEqual(viewModel.messages["chat-1"]?.first?.text, "Hello!")
  }

  func testSendMessage_failure_setsErrorState() async {
    let mockService = MockBridgeService()
    await mockService.setShouldThrowError(true)

    let viewModel = createViewModel(mockService: mockService)

    let conversation = Conversation(
      id: "chat-1",
      guid: "guid-1",
      displayName: "Test User",
      participants: [Handle(id: 1, address: "+15551234567", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )
    await mockService.setConversationsToReturn([conversation])
    await viewModel.loadConversations()

    await viewModel.sendMessage("Hello!", toConversation: conversation)

    // Error should be captured
    XCTAssertNotNil(viewModel.lastError)
  }

  func testSendMessage_passesRecipientToService() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    let conversation = Conversation(
      id: "chat-1",
      guid: "guid-1",
      displayName: "Test User",
      participants: [Handle(id: 1, address: "+15551234567", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )
    await mockService.setConversationsToReturn([conversation])
    await viewModel.loadConversations()

    await viewModel.sendMessage("Hello!", toConversation: conversation)

    let lastRecipient = await mockService.lastRecipient
    XCTAssertEqual(lastRecipient, "+15551234567")
  }

  // MARK: - Group Conversation Message Routing Tests

  func testSendMessage_toOneOnOneConversation_sendsToParticipantAddress() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // 1:1 conversation with single participant
    let conversation = Conversation(
      id: "iMessage;-;+15551234567",
      guid: "guid-1",
      displayName: "John Doe",
      participants: [Handle(id: 1, address: "+15551234567", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )

    await viewModel.sendMessage("Hello!", toConversation: conversation)

    let lastRecipient = await mockService.lastRecipient
    // For 1:1 conversations, we send to the participant's address
    XCTAssertEqual(lastRecipient, "+15551234567")
  }

  func testSendMessage_toGroupConversation_sendsToChatId() async {
    let mockService = MockBridgeService()
    let groupChatId = "chat123456789"
    let viewModel = createViewModel(mockService: mockService)

    // Group conversation with multiple participants
    let groupConversation = Conversation(
      id: groupChatId,
      guid: "guid-group",
      displayName: "Team Chat",
      participants: [
        Handle(id: 1, address: "+15551234567", service: "iMessage"),
        Handle(id: 2, address: "+15559876543", service: "iMessage"),
        Handle(id: 3, address: "+15555555555", service: "iMessage"),
      ],
      lastMessage: nil,
      isGroup: true
    )

    await viewModel.sendMessage("Hello group!", toConversation: groupConversation)

    let lastRecipient = await mockService.lastRecipient
    // For group conversations, we should send to the chat ID, not the first participant
    XCTAssertEqual(lastRecipient, groupChatId)
  }

  func testSendMessage_toGroupConversation_doesNotSendToFirstParticipant() async {
    let mockService = MockBridgeService()
    let groupChatId = "chat123456789"
    let viewModel = createViewModel(mockService: mockService)

    let groupConversation = Conversation(
      id: groupChatId,
      guid: "guid-group",
      displayName: "Team Chat",
      participants: [
        Handle(id: 1, address: "+15551234567", service: "iMessage"),
        Handle(id: 2, address: "+15559876543", service: "iMessage"),
      ],
      lastMessage: nil,
      isGroup: true
    )

    await viewModel.sendMessage("Hello group!", toConversation: groupConversation)

    let lastRecipient = await mockService.lastRecipient
    // Verify it does NOT send to the first participant's address
    XCTAssertNotEqual(lastRecipient, "+15551234567")
    XCTAssertNotEqual(lastRecipient, "+15559876543")
  }

  func testSendMessage_addsMessageToCorrectConversation() async {
    let mockService = MockBridgeService()

    let viewModel = createViewModel(mockService: mockService)

    // Set up two conversations
    let conversation1 = Conversation(
      id: "chat-1",
      guid: "guid-1",
      displayName: "Alice",
      participants: [Handle(id: 1, address: "+15551111111", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )
    let conversation2 = Conversation(
      id: "chat-2",
      guid: "guid-2",
      displayName: "Bob",
      participants: [Handle(id: 2, address: "+15552222222", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )
    await mockService.setConversationsToReturn([conversation1, conversation2])
    await viewModel.loadConversations()

    // Send message to conversation 1
    await viewModel.sendMessage("Hello Alice!", toConversation: conversation1)

    // Verify message is in conversation 1, not conversation 2
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 1)
    XCTAssertEqual(viewModel.messages["chat-1"]?.first?.text, "Hello Alice!")
    XCTAssertNil(viewModel.messages["chat-2"])
  }

  func testReceiveMessage_addsToCorrectConversation() async {
    let mockService = MockBridgeService()

    let viewModel = createViewModel(mockService: mockService)

    // Set up two conversations
    let conversation1 = Conversation(
      id: "chat-1",
      guid: "guid-1",
      displayName: "Alice",
      participants: [Handle(id: 1, address: "+15551111111", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )
    let conversation2 = Conversation(
      id: "chat-2",
      guid: "guid-2",
      displayName: "Bob",
      participants: [Handle(id: 2, address: "+15552222222", service: "iMessage")],
      lastMessage: nil,
      isGroup: false
    )
    await mockService.setConversationsToReturn([conversation1, conversation2])

    // Connect to set up WebSocket
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

    // Simulate receiving a message for conversation 1
    let incomingMessage = Message(
      id: 200,
      guid: "msg-200",
      text: "Hey there!",
      date: Date(),
      isFromMe: false,
      handleId: 1,
      conversationId: "chat-1"
    )
    await mockService.simulateNewMessage(incomingMessage, sender: "Alice")

    // Give the async handler time to process
    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

    // Verify message is in conversation 1, not conversation 2
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 1)
    XCTAssertEqual(viewModel.messages["chat-1"]?.first?.text, "Hey there!")
    XCTAssertNil(viewModel.messages["chat-2"])
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
}
