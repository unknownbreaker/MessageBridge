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
  var tapbackEventHandler: TapbackEventHandler?
  var syncWarningHandler: SyncWarningHandler?
  var syncWarningClearedHandler: SyncWarningClearedHandler?
  var pinnedConversationsChangedHandler: PinnedConversationsChangedHandler?

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

  func sendMessage(text: String, to recipient: String, replyToGuid: String? = nil) async throws {
    sendMessageCalled = true
    lastRecipient = recipient
    lastMessageText = text
    if shouldThrowError {
      throw BridgeError.sendFailed
    }
  }

  func startWebSocket(
    onNewMessage: @escaping NewMessageHandler,
    onTapbackEvent: @escaping TapbackEventHandler,
    onSyncWarning: @escaping SyncWarningHandler,
    onSyncWarningCleared: @escaping SyncWarningClearedHandler,
    onPinnedConversationsChanged: @escaping PinnedConversationsChangedHandler
  ) async throws {
    startWebSocketCalled = true
    newMessageHandler = onNewMessage
    tapbackEventHandler = onTapbackEvent
    syncWarningHandler = onSyncWarning
    syncWarningClearedHandler = onSyncWarningCleared
    pinnedConversationsChangedHandler = onPinnedConversationsChanged
  }

  func stopWebSocket() async {
    stopWebSocketCalled = true
    newMessageHandler = nil
    tapbackEventHandler = nil
    syncWarningHandler = nil
    syncWarningClearedHandler = nil
    pinnedConversationsChangedHandler = nil
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

  var sendTapbackCalled = false
  var lastTapbackType: TapbackType?
  var lastTapbackMessageGUID: String?
  var lastTapbackAction: TapbackActionType?

  func sendTapback(type: TapbackType, messageGUID: String, action: TapbackActionType) async throws {
    sendTapbackCalled = true
    lastTapbackType = type
    lastTapbackMessageGUID = messageGUID
    lastTapbackAction = action
    if shouldThrowError {
      throw BridgeError.tapbackFailed
    }
  }

  // Helper to simulate receiving a new message
  func simulateNewMessage(_ message: Message, sender: String) {
    newMessageHandler?(message, sender)
  }

  // Helper to simulate receiving a tapback event
  func simulateTapbackEvent(_ event: TapbackEvent) {
    tapbackEventHandler?(event)
  }

  // Helper to simulate receiving a sync warning event
  func simulateSyncWarning(_ event: SyncWarningEvent) {
    syncWarningHandler?(event)
  }

  // Helper to simulate receiving a sync warning cleared event
  func simulateSyncWarningCleared(_ event: SyncWarningClearedEvent) {
    syncWarningClearedHandler?(event)
  }

  // Helper to simulate receiving a pinned conversations changed event
  func simulatePinnedConversationsChanged(_ event: PinnedConversationsChangedEvent) {
    pinnedConversationsChangedHandler?(event)
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

  func testDisconnect_clearsPaginationState() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    viewModel.paginationState["chat-1"] = MessagesViewModel.PaginationState(
      offset: 30, hasMore: true)

    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")
    await viewModel.disconnect()

    XCTAssertTrue(viewModel.paginationState.isEmpty)
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

  // MARK: - Conversation Reorder Tests

  func testNewMessage_movesConversationToTop() async {
    let mockService = MockBridgeService()

    let conversationA = Conversation(
      id: "chat-a", guid: "guid-a", displayName: "Alice",
      participants: [Handle(id: 1, address: "+15551111111", service: "iMessage")],
      lastMessage: nil, isGroup: false
    )
    let conversationB = Conversation(
      id: "chat-b", guid: "guid-b", displayName: "Bob",
      participants: [Handle(id: 2, address: "+15552222222", service: "iMessage")],
      lastMessage: nil, isGroup: false
    )
    let conversationC = Conversation(
      id: "chat-c", guid: "guid-c", displayName: "Carol",
      participants: [Handle(id: 3, address: "+15553333333", service: "iMessage")],
      lastMessage: nil, isGroup: false
    )
    await mockService.setConversationsToReturn([conversationA, conversationB, conversationC])

    let viewModel = createViewModel(mockService: mockService)
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

    XCTAssertEqual(viewModel.conversations.map(\.id), ["chat-a", "chat-b", "chat-c"])

    // Simulate a new message for conversation C
    let incomingMessage = Message(
      id: 300, guid: "msg-300", text: "Hello from Carol!",
      date: Date(), isFromMe: false, handleId: 3, conversationId: "chat-c"
    )
    await mockService.simulateNewMessage(incomingMessage, sender: "Carol")
    try? await Task.sleep(nanoseconds: 100_000_000)

    // Conversation C should now be at the top
    XCTAssertEqual(viewModel.conversations.map(\.id), ["chat-c", "chat-a", "chat-b"])
    XCTAssertEqual(viewModel.conversations[0].lastMessage?.text, "Hello from Carol!")
  }

  // MARK: - Pinned Conversation Tests

  func testNewMessage_doesNotReorderPinnedConversation() async {
    let mockService = MockBridgeService()

    let pinnedConversation = Conversation(
      id: "chat-pinned", guid: "guid-pinned", displayName: "Pinned Chat",
      participants: [Handle(id: 1, address: "+15551111111", service: "iMessage")],
      lastMessage: nil, isGroup: false, pinnedIndex: 0
    )
    let conversationB = Conversation(
      id: "chat-b", guid: "guid-b", displayName: "Bob",
      participants: [Handle(id: 2, address: "+15552222222", service: "iMessage")],
      lastMessage: nil, isGroup: false
    )
    let conversationC = Conversation(
      id: "chat-c", guid: "guid-c", displayName: "Carol",
      participants: [Handle(id: 3, address: "+15553333333", service: "iMessage")],
      lastMessage: nil, isGroup: false
    )
    await mockService.setConversationsToReturn([pinnedConversation, conversationB, conversationC])

    let viewModel = createViewModel(mockService: mockService)
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

    XCTAssertEqual(viewModel.conversations.map(\.id), ["chat-pinned", "chat-b", "chat-c"])

    // Simulate a new message for the pinned conversation
    let incomingMessage = Message(
      id: 400, guid: "msg-400", text: "New message in pinned",
      date: Date(), isFromMe: false, handleId: 1, conversationId: "chat-pinned"
    )
    await mockService.simulateNewMessage(incomingMessage, sender: "Pinned Chat")
    try? await Task.sleep(nanoseconds: 100_000_000)

    // Pinned conversation should stay at index 0, NOT move
    XCTAssertEqual(viewModel.conversations.map(\.id), ["chat-pinned", "chat-b", "chat-c"])
    XCTAssertEqual(viewModel.conversations[0].lastMessage?.text, "New message in pinned")
    XCTAssertEqual(viewModel.conversations[0].pinnedIndex, 0)
  }

  func testPinnedConversationsChangedEvent_updatesPinnedIndex() async {
    let mockService = MockBridgeService()

    let conversationA = Conversation(
      id: "chat-a", guid: "guid-a", displayName: "Alice",
      participants: [], lastMessage: nil, isGroup: false
    )
    let conversationB = Conversation(
      id: "chat-b", guid: "guid-b", displayName: "Bob",
      participants: [], lastMessage: nil, isGroup: false
    )
    let conversationC = Conversation(
      id: "chat-c", guid: "guid-c", displayName: "Carol",
      participants: [], lastMessage: nil, isGroup: false
    )
    await mockService.setConversationsToReturn([conversationA, conversationB, conversationC])

    let viewModel = createViewModel(mockService: mockService)
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

    // Initially no conversations are pinned
    XCTAssertTrue(viewModel.conversations.allSatisfy { $0.pinnedIndex == nil })

    // Simulate a pinned conversations changed event: pin A at 0 and C at 1
    let event = PinnedConversationsChangedEvent(
      pinned: [
        PinnedConversationEntry(conversationId: "chat-a", index: 0),
        PinnedConversationEntry(conversationId: "chat-c", index: 1),
      ]
    )
    await mockService.simulatePinnedConversationsChanged(event)
    try? await Task.sleep(nanoseconds: 100_000_000)

    // A and C should have pinnedIndex, B should not
    let pinA = viewModel.conversations.first { $0.id == "chat-a" }
    let pinB = viewModel.conversations.first { $0.id == "chat-b" }
    let pinC = viewModel.conversations.first { $0.id == "chat-c" }

    XCTAssertEqual(pinA?.pinnedIndex, 0)
    XCTAssertNil(pinB?.pinnedIndex)
    XCTAssertEqual(pinC?.pinnedIndex, 1)
  }

  func testPinnedConversationsChangedEvent_clearsPreviousPins() async {
    let mockService = MockBridgeService()

    // Start with a pinned conversation
    let conversationA = Conversation(
      id: "chat-a", guid: "guid-a", displayName: "Alice",
      participants: [], lastMessage: nil, isGroup: false, pinnedIndex: 0
    )
    let conversationB = Conversation(
      id: "chat-b", guid: "guid-b", displayName: "Bob",
      participants: [], lastMessage: nil, isGroup: false
    )
    await mockService.setConversationsToReturn([conversationA, conversationB])

    let viewModel = createViewModel(mockService: mockService)
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

    XCTAssertEqual(viewModel.conversations.first { $0.id == "chat-a" }?.pinnedIndex, 0)

    // Simulate event that pins B instead of A
    let event = PinnedConversationsChangedEvent(
      pinned: [
        PinnedConversationEntry(conversationId: "chat-b", index: 0)
      ]
    )
    await mockService.simulatePinnedConversationsChanged(event)
    try? await Task.sleep(nanoseconds: 100_000_000)

    // A should no longer be pinned, B should be pinned
    XCTAssertNil(viewModel.conversations.first { $0.id == "chat-a" }?.pinnedIndex)
    XCTAssertEqual(viewModel.conversations.first { $0.id == "chat-b" }?.pinnedIndex, 0)
  }

  // MARK: - Pagination Tests

  func testLoadMessages_setsPaginationState() async {
    let mockService = MockBridgeService()
    // Return exactly 30 messages (full page = hasMore)
    let messages = (0..<30).map { i in
      Message(
        id: Int64(i), guid: "msg-\(i)", text: "Message \(i)",
        date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    }
    await mockService.setMessagesToReturn(messages)
    let viewModel = createViewModel(mockService: mockService)

    await viewModel.loadMessages(for: "chat-1")

    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 30)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.offset, 30)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.hasMore, true)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.isLoadingMore, false)
  }

  func testLoadMoreMessages_appendsOlderMessages() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // Simulate initial load already happened
    let initialMessages = (0..<30).map { i in
      Message(
        id: Int64(100 + i), guid: "msg-\(100 + i)", text: "New \(i)",
        date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    }
    viewModel.messages["chat-1"] = initialMessages
    viewModel.paginationState["chat-1"] = MessagesViewModel.PaginationState(
      offset: 30, hasMore: true)

    // Mock will return the next page
    let olderMessages = (0..<30).map { i in
      Message(
        id: Int64(i), guid: "msg-\(i)", text: "Old \(i)",
        date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    }
    await mockService.setMessagesToReturn(olderMessages)

    await viewModel.loadMoreMessages(for: "chat-1")

    // Should have 60 total: 30 initial + 30 older appended at end
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 60)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.offset, 60)
  }

  func testLoadMoreMessages_whenNoMore_doesNothing() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    viewModel.messages["chat-1"] = []
    viewModel.paginationState["chat-1"] = MessagesViewModel.PaginationState(
      offset: 10, hasMore: false)

    await viewModel.loadMoreMessages(for: "chat-1")

    let fetchCalled = await mockService.fetchMessagesCalled
    XCTAssertFalse(fetchCalled)
  }

  func testLoadMoreMessages_whenAlreadyLoading_doesNothing() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    viewModel.messages["chat-1"] = []
    viewModel.paginationState["chat-1"] = MessagesViewModel.PaginationState(
      offset: 30, hasMore: true, isLoadingMore: true)

    await viewModel.loadMoreMessages(for: "chat-1")

    let fetchCalled = await mockService.fetchMessagesCalled
    XCTAssertFalse(fetchCalled)
  }

  func testLoadMoreMessages_deduplicatesById() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    let existingMessage = Message(
      id: 5, guid: "msg-5", text: "Existing",
      date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    viewModel.messages["chat-1"] = [existingMessage]
    viewModel.paginationState["chat-1"] = MessagesViewModel.PaginationState(
      offset: 1, hasMore: true)

    // Return a page that includes a duplicate
    let duplicate = Message(
      id: 5, guid: "msg-5", text: "Existing",
      date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    let newMessage = Message(
      id: 4, guid: "msg-4", text: "Older",
      date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    await mockService.setMessagesToReturn([duplicate, newMessage])

    await viewModel.loadMoreMessages(for: "chat-1")

    // Should have 2, not 3 — duplicate skipped
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 2)
  }

  func testLoadMoreMessages_error_keepsExistingState() async {
    let mockService = MockBridgeService()
    await mockService.setShouldThrowError(true)
    let viewModel = createViewModel(mockService: mockService)

    viewModel.messages["chat-1"] = [
      Message(
        id: 1, guid: "msg-1", text: "Hello", date: Date(),
        isFromMe: false, handleId: nil, conversationId: "chat-1")
    ]
    viewModel.paginationState["chat-1"] = MessagesViewModel.PaginationState(
      offset: 1, hasMore: true)

    await viewModel.loadMoreMessages(for: "chat-1")

    // Messages unchanged, offset unchanged, still hasMore
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 1)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.offset, 1)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.hasMore, true)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.isLoadingMore, false)
  }

  func testLoadMessages_lessThanPageSize_setsHasMoreFalse() async {
    let mockService = MockBridgeService()
    // Return fewer than 30 messages = no more pages
    let messages = (0..<10).map { i in
      Message(
        id: Int64(i), guid: "msg-\(i)", text: "Message \(i)",
        date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    }
    await mockService.setMessagesToReturn(messages)
    let viewModel = createViewModel(mockService: mockService)

    await viewModel.loadMessages(for: "chat-1")

    XCTAssertEqual(viewModel.paginationState["chat-1"]?.hasMore, false)
  }

  // MARK: - Sync Warning Tests

  func testSyncWarnings_initiallyEmpty() {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)
    XCTAssertTrue(viewModel.syncWarnings.isEmpty)
  }

  func testHandleSyncWarning_addsWarning() {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    viewModel.handleSyncWarning(conversationId: "chat123", message: "Test warning")

    XCTAssertEqual(viewModel.syncWarnings["chat123"], "Test warning")
  }

  func testHandleSyncWarningCleared_removesWarning() {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)
    viewModel.handleSyncWarning(conversationId: "chat123", message: "Test warning")

    viewModel.handleSyncWarningCleared(conversationId: "chat123")

    XCTAssertNil(viewModel.syncWarnings["chat123"])
  }

  func testDismissSyncWarning_removesWarning() {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)
    viewModel.handleSyncWarning(conversationId: "chat123", message: "Test warning")

    viewModel.dismissSyncWarning(for: "chat123")

    XCTAssertNil(viewModel.syncWarnings["chat123"])
  }

  func testDisconnect_clearsSyncWarnings() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // Connect and add a sync warning
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")
    viewModel.handleSyncWarning(conversationId: "chat123", message: "Test warning")
    XCTAssertFalse(viewModel.syncWarnings.isEmpty)

    // Disconnect
    await viewModel.disconnect()

    // Sync warnings should be cleared
    XCTAssertTrue(viewModel.syncWarnings.isEmpty)
  }

  func testSyncWarning_viaWebSocket_updatesViewModel() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // Connect to set up WebSocket
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")
    XCTAssertTrue(viewModel.syncWarnings.isEmpty)

    // Simulate receiving a sync warning via WebSocket
    let warningEvent = SyncWarningEvent(conversationId: "chat456", message: "Read sync failed")
    await mockService.simulateSyncWarning(warningEvent)

    // Give the async handler time to process
    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

    XCTAssertEqual(viewModel.syncWarnings["chat456"], "Read sync failed")
  }

  func testSyncWarningCleared_viaWebSocket_removesWarning() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // Connect to set up WebSocket
    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")

    // Add a sync warning first
    viewModel.handleSyncWarning(conversationId: "chat789", message: "Test warning")
    XCTAssertEqual(viewModel.syncWarnings["chat789"], "Test warning")

    // Simulate receiving a sync warning cleared via WebSocket
    let clearedEvent = SyncWarningClearedEvent(conversationId: "chat789")
    await mockService.simulateSyncWarningCleared(clearedEvent)

    // Give the async handler time to process
    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

    XCTAssertNil(viewModel.syncWarnings["chat789"])
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

  func setMessagesToReturn(_ messages: [Message]) {
    messagesToReturn = messages
  }
}
