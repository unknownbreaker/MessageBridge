import AppKit
import Combine
import Foundation
import SwiftUI

public enum ConnectionStatus: Sendable {
  case connected
  case connecting
  case disconnected
}

@MainActor
public class MessagesViewModel: ObservableObject {
  @Published public var conversations: [Conversation] = []
  @Published public var messages: [String: [Message]] = [:]
  @Published public var connectionStatus: ConnectionStatus = .disconnected
  @Published public var lastError: Error?
  @Published public var selectedConversationId: String?
  @Published public var syncWarnings: [String: String] = [:]  // conversationId -> warning message

  public struct PaginationState {
    public var offset: Int = 0
    public var hasMore: Bool = true
    public var isLoadingMore: Bool = false

    public init(offset: Int = 0, hasMore: Bool = true, isLoadingMore: Bool = false) {
      self.offset = offset
      self.hasMore = hasMore
      self.isLoadingMore = isLoadingMore
    }
  }

  public var paginationState: [String: PaginationState] = [:]

  private let pageSize = 30

  private let bridgeService: any BridgeServiceProtocol
  private let notificationManager: NotificationManager
  private var cancellables = Set<AnyCancellable>()
  private var markAsReadTask: Task<Void, Never>?

  /// Total unread message count across all conversations
  public var totalUnreadCount: Int {
    conversations.reduce(0) { $0 + $1.unreadCount }
  }

  public init(
    bridgeService: any BridgeServiceProtocol = BridgeConnection(),
    notificationManager: NotificationManager = NotificationManager()
  ) {
    self.bridgeService = bridgeService
    self.notificationManager = notificationManager

    // Observe conversations changes and update dock badge automatically
    $conversations
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateDockBadge()
      }
      .store(in: &cancellables)
  }

  /// Updates the dock badge to show total unread count
  public func updateDockBadge() {
    // Guard against nil NSApp in test environments
    guard let app = NSApp else { return }

    let count = totalUnreadCount
    if count > 0 {
      app.dockTile.badgeLabel = "\(count)"
    } else {
      app.dockTile.badgeLabel = nil
    }
  }

  public func requestNotificationPermission() async {
    do {
      _ = try await notificationManager.requestAuthorization()
    } catch {
      logWarning("Failed to request notification permission: \(error.localizedDescription)")
    }
  }

  public func connect(to serverURL: URL, apiKey: String, e2eEnabled: Bool = false) async {
    connectionStatus = .connecting
    do {
      try await bridgeService.connect(to: serverURL, apiKey: apiKey, e2eEnabled: e2eEnabled)
      connectionStatus = .connected
      logInfo("Connected to server\(e2eEnabled ? " with E2E encryption" : "")")
      await loadConversations()
      await startWebSocket()
    } catch {
      connectionStatus = .disconnected
      logError("Connection failed", error: error)
    }
  }

  public func disconnect() async {
    await bridgeService.disconnect()
    connectionStatus = .disconnected
    conversations = []
    messages = [:]
    paginationState = [:]
    selectedConversationId = nil
    syncWarnings = [:]  // Clear sync warnings on disconnect
    updateDockBadge()  // Clear badge on disconnect
    logInfo("Disconnected from server")
  }

  public func reconnect() async {
    // Disconnect first
    await disconnect()

    // Load saved config and reconnect
    let keychainManager = KeychainManager()
    guard let config = try? keychainManager.retrieveServerConfig() else {
      logError("No saved server configuration found")
      return
    }

    await connect(to: config.serverURL, apiKey: config.apiKey, e2eEnabled: true)
  }

  // MARK: - Sync Warning Handling

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

  // MARK: - Pinned Conversations Handling

  /// Handle pinned conversations changed event from WebSocket
  public func handlePinnedConversationsChanged(_ event: PinnedConversationsChangedEvent) {
    // Build a map of conversationId -> pinnedIndex
    let pinMap = Dictionary(
      uniqueKeysWithValues: event.pinned.map { ($0.conversationId, $0.index) })

    // Update all conversations with new pin state
    conversations = conversations.map { conversation in
      let newPinnedIndex = pinMap[conversation.id]
      if newPinnedIndex != conversation.pinnedIndex {
        return Conversation(
          id: conversation.id,
          guid: conversation.guid,
          displayName: conversation.rawDisplayName,
          participants: conversation.participants,
          lastMessage: conversation.lastMessage,
          isGroup: conversation.isGroup,
          groupPhotoBase64: conversation.groupPhotoBase64,
          unreadCount: conversation.unreadCount,
          pinnedIndex: newPinnedIndex
        )
      }
      return conversation
    }
  }

  private func startWebSocket() async {
    do {
      try await bridgeService.startWebSocket(
        onNewMessage: { [weak self] message, sender in
          Task { @MainActor [weak self] in
            await self?.handleNewMessage(message, sender: sender)
          }
        },
        onTapbackEvent: { [weak self] event in
          Task { @MainActor [weak self] in
            self?.handleTapbackEvent(event)
          }
        },
        onSyncWarning: { [weak self] event in
          Task { @MainActor [weak self] in
            self?.handleSyncWarning(conversationId: event.conversationId, message: event.message)
          }
        },
        onSyncWarningCleared: { [weak self] event in
          Task { @MainActor [weak self] in
            self?.handleSyncWarningCleared(conversationId: event.conversationId)
          }
        },
        onPinnedConversationsChanged: { [weak self] event in
          Task { @MainActor [weak self] in
            self?.handlePinnedConversationsChanged(event)
          }
        }
      )
      logInfo("WebSocket connection started")
    } catch {
      logError("Failed to start WebSocket", error: error)
    }
  }

  private func handleNewMessage(_ message: Message, sender: String) async {
    // Add message to the conversation
    let conversationId = message.conversationId
    logDebug(
      "handleNewMessage: received message for conversation \(conversationId), text: \(message.text ?? "nil"), isFromMe: \(message.isFromMe)"
    )

    // Create new array to trigger @Published update (mutating in place doesn't trigger SwiftUI refresh)
    var updatedMessages = messages[conversationId, default: []]

    // If this is a message from me, check if we have an optimistic version (negative ID) to replace
    if message.isFromMe {
      // Look for an optimistic message with matching text (optimistic messages have negative IDs)
      if let optimisticIndex = updatedMessages.firstIndex(where: {
        $0.id < 0 && $0.text == message.text
      }) {
        // Replace optimistic message with the real one
        updatedMessages.remove(at: optimisticIndex)
        updatedMessages.insert(message, at: optimisticIndex)
        logDebug("handleNewMessage: replaced optimistic message with real message ID \(message.id)")
      } else {
        // No optimistic message found - this might be from another device, so add it
        updatedMessages.insert(message, at: 0)
        logDebug("handleNewMessage: added message from me (no optimistic version found)")
      }
    } else {
      // Message from someone else - always add it
      updatedMessages.insert(message, at: 0)
    }

    messages[conversationId] = updatedMessages
    logDebug("handleNewMessage: updated messages array, now has \(updatedMessages.count) messages")

    // Update conversation's last message and unread count
    if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
      logDebug("handleNewMessage: found conversation at index \(index)")
      let existingConversation = conversations[index]

      // Increment unread count if message is not from me AND conversation is not currently selected
      let newUnreadCount: Int
      if !message.isFromMe && selectedConversationId != conversationId {
        newUnreadCount = existingConversation.unreadCount + 1
      } else {
        newUnreadCount = existingConversation.unreadCount
      }

      let updatedConversation = Conversation(
        id: existingConversation.id,
        guid: existingConversation.guid,
        displayName: existingConversation.rawDisplayName,
        participants: existingConversation.participants,
        lastMessage: message,
        isGroup: existingConversation.isGroup,
        groupPhotoBase64: existingConversation.groupPhotoBase64,
        unreadCount: newUnreadCount,
        pinnedIndex: existingConversation.pinnedIndex
      )
      // Move conversation to top of list — but only if it's not pinned
      var newConversations = conversations
      newConversations.remove(at: index)
      if existingConversation.pinnedIndex != nil {
        // Pinned conversations stay in their original position
        newConversations.insert(updatedConversation, at: index)
      } else {
        newConversations.insert(updatedConversation, at: 0)
      }
      conversations = newConversations
      logDebug("handleNewMessage: updated conversation lastMessage to: \(message.text ?? "nil")")

      // Update dock badge if unread count changed
      if newUnreadCount != existingConversation.unreadCount {
        updateDockBadge()
      }
    } else {
      logWarning("handleNewMessage: conversation not found for id \(conversationId)")
    }

    // Show notification if message is not from me and conversation is not selected
    if !message.isFromMe && selectedConversationId != conversationId {
      do {
        try await notificationManager.showNotification(for: message, senderName: sender)
      } catch {
        logWarning("Failed to show notification: \(error.localizedDescription)")
      }
    }
  }

  /// Handle a tapback event from WebSocket (tapback added or removed)
  private func handleTapbackEvent(_ event: TapbackEvent) {
    let conversationId = event.conversationId
    logDebug(
      "handleTapbackEvent: \(event.isRemoval ? "removed" : "added") \(event.tapbackType.emoji) on message \(event.messageGUID)"
    )

    // Find the message in our local cache
    guard var conversationMessages = messages[conversationId] else {
      logDebug("handleTapbackEvent: conversation \(conversationId) not loaded, ignoring")
      return
    }

    guard
      let messageIndex = conversationMessages.firstIndex(where: { $0.guid == event.messageGUID })
    else {
      logDebug("handleTapbackEvent: message \(event.messageGUID) not found in conversation")
      return
    }

    let message = conversationMessages[messageIndex]
    var tapbacks = message.tapbacks ?? []

    if event.isRemoval {
      // Remove the tapback from this sender with matching type
      tapbacks.removeAll { tapback in
        tapback.sender == event.sender && tapback.type == event.tapbackType
      }
      logDebug(
        "handleTapbackEvent: removed tapback, now has \(tapbacks.count) tapbacks")
    } else {
      // Add the new tapback
      let newTapback = Tapback(
        type: event.tapbackType,
        sender: event.sender,
        isFromMe: event.isFromMe,
        date: Date(),
        messageGUID: event.messageGUID,
        emoji: event.emoji
      )

      // Remove any existing tapback from this sender (user can only have one tapback per message)
      tapbacks.removeAll { $0.sender == event.sender }
      tapbacks.append(newTapback)
      logDebug(
        "handleTapbackEvent: added tapback, now has \(tapbacks.count) tapbacks")
    }

    // Create updated message with new tapbacks
    let updatedMessage = Message(
      id: message.id,
      guid: message.guid,
      text: message.text,
      date: message.date,
      isFromMe: message.isFromMe,
      handleId: message.handleId,
      conversationId: message.conversationId,
      attachments: message.attachments,
      detectedCodes: message.detectedCodes,
      highlights: message.highlights,
      mentions: message.mentions,
      tapbacks: tapbacks.isEmpty ? nil : tapbacks
    )

    // Update the messages array to trigger UI refresh
    conversationMessages[messageIndex] = updatedMessage
    messages[conversationId] = conversationMessages
    logDebug("handleTapbackEvent: updated message in cache")
  }

  public func selectConversation(_ conversationId: String?) {
    logDebug("Selecting conversation: \(conversationId ?? "nil")")
    selectedConversationId = conversationId

    // Handle conversation selection
    if let id = conversationId {
      // Clear notifications for this conversation
      Task {
        await notificationManager.clearNotifications(for: id)
      }

      // Update local unread count if needed
      if let index = conversations.firstIndex(where: { $0.id == id }),
        conversations[index].unreadCount > 0
      {
        // Reset local unread count immediately for responsive UI
        let existingConversation = conversations[index]
        let updatedConversation = Conversation(
          id: existingConversation.id,
          guid: existingConversation.guid,
          displayName: existingConversation.rawDisplayName,
          participants: existingConversation.participants,
          lastMessage: existingConversation.lastMessage,
          isGroup: existingConversation.isGroup,
          groupPhotoBase64: existingConversation.groupPhotoBase64,
          unreadCount: 0,
          pinnedIndex: existingConversation.pinnedIndex
        )
        // Force SwiftUI to detect change by creating a new array
        var newConversations = conversations
        newConversations[index] = updatedConversation
        conversations = newConversations

        // Update dock badge after clearing unread count
        updateDockBadge()
      }

      // Cancel any in-flight mark-as-read (stops previous UI search AppleScript)
      markAsReadTask?.cancel()

      // Mark as read in database (syncs with Messages.app)
      markAsReadTask = Task {
        do {
          try await bridgeService.markConversationAsRead(id)
          logDebug("Marked conversation \(id) as read on server")
        } catch is CancellationError {
          logDebug("Mark-as-read cancelled for \(id)")
        } catch {
          logWarning("Failed to mark conversation as read: \(error.localizedDescription)")
        }
      }
    }
  }

  public func loadConversations() async {
    do {
      conversations = try await bridgeService.fetchConversations(limit: 50, offset: 0)
      logDebug("Loaded \(conversations.count) conversations")
      updateDockBadge()
    } catch {
      logError("Failed to load conversations", error: error)
    }
  }

  public func loadMessages(for conversationId: String) async {
    logDebug("Loading messages for conversation: \(conversationId)")
    do {
      let msgs = try await bridgeService.fetchMessages(
        conversationId: conversationId, limit: pageSize, offset: 0)
      messages[conversationId] = msgs
      paginationState[conversationId] = PaginationState(
        offset: msgs.count,
        hasMore: msgs.count >= pageSize,
        isLoadingMore: false
      )
      logDebug("Loaded \(msgs.count) messages for conversation \(conversationId)")
    } catch {
      logError("Failed to load messages for conversation \(conversationId)", error: error)
    }
  }

  public func loadMoreMessages(for conversationId: String) async {
    guard var state = paginationState[conversationId],
      state.hasMore, !state.isLoadingMore
    else { return }

    state.isLoadingMore = true
    paginationState[conversationId] = state

    do {
      let olderMessages = try await bridgeService.fetchMessages(
        conversationId: conversationId, limit: pageSize, offset: state.offset)

      // Deduplicate by ID
      let existingIds = Set(messages[conversationId, default: []].map { $0.id })
      let newMessages = olderMessages.filter { !existingIds.contains($0.id) }

      messages[conversationId, default: []].append(contentsOf: newMessages)
      paginationState[conversationId] = PaginationState(
        offset: state.offset + olderMessages.count,
        hasMore: olderMessages.count >= pageSize,
        isLoadingMore: false
      )
      logDebug("Loaded \(newMessages.count) more messages for \(conversationId)")
    } catch {
      state.isLoadingMore = false
      paginationState[conversationId] = state
      logError("Failed to load more messages for \(conversationId)", error: error)
    }
  }

  public func fetchAttachment(id: Int64) async throws -> Data {
    return try await bridgeService.fetchAttachment(id: id)
  }

  public func sendMessage(
    _ text: String, toConversation conversation: Conversation, replyToGuid: String? = nil
  ) async {
    // Clear any previous error
    lastError = nil

    // Determine the recipient:
    // - For 1:1 conversations: use the participant's address
    // - For group conversations: use the conversation ID (chat_identifier)
    let recipient: String
    if conversation.isGroup {
      // Group chats: send to the chat ID directly
      recipient = conversation.id
    } else {
      // 1:1 chats: send to the participant's address
      guard let participantAddress = conversation.participants.first?.address else {
        lastError = BridgeError.sendFailed
        return
      }
      recipient = participantAddress
    }

    let conversationId = conversation.id

    // Optimistic UI update: show message immediately
    let optimisticMessage = Message(
      id: Int64.random(in: Int64.min..<0),  // Negative ID to indicate pending
      guid: UUID().uuidString,
      text: text,
      date: Date(),
      isFromMe: true,
      handleId: nil,
      conversationId: conversationId,
      replyToGuid: replyToGuid
    )
    messages[conversationId, default: []].insert(optimisticMessage, at: 0)

    do {
      try await bridgeService.sendMessage(text: text, to: recipient, replyToGuid: replyToGuid)
      // Send succeeded - keep the optimistic message
      // The real message will arrive via WebSocket and replace it
      logDebug("Message sent successfully to \(recipient)")
    } catch {
      // Remove optimistic message on failure
      messages[conversationId]?.removeAll { $0.guid == optimisticMessage.guid }
      lastError = error
      logError("Failed to send message to \(recipient)", error: error)
    }
  }

  /// Send a tapback reaction to a message with optimistic local update
  /// - Parameters:
  ///   - type: The type of tapback (love, like, dislike, laugh, emphasis, question)
  ///   - messageGUID: The GUID of the message to react to
  ///   - action: Whether to add or remove the tapback
  ///   - conversationId: The conversation containing the message
  public func sendTapback(
    type: TapbackType, messageGUID: String, action: TapbackActionType, conversationId: String
  ) async {
    // Find the message in local cache
    guard var conversationMessages = messages[conversationId],
      let messageIndex = conversationMessages.firstIndex(where: { $0.guid == messageGUID })
    else {
      // Message not in cache, fall through to server-only request
      do {
        try await bridgeService.sendTapback(type: type, messageGUID: messageGUID, action: action)
        logDebug("Tapback \(action.rawValue) sent successfully for message \(messageGUID)")
      } catch {
        logError("Failed to send tapback", error: error)
        lastError = error
      }
      return
    }

    let message = conversationMessages[messageIndex]
    let previousTapbacks = message.tapbacks

    // Optimistically update tapbacks
    var tapbacks = message.tapbacks ?? []
    switch action {
    case .remove:
      tapbacks.removeAll { $0.isFromMe && $0.type == type }
    case .add:
      // Remove any existing tapback from me (one per user per message)
      tapbacks.removeAll { $0.isFromMe }
      tapbacks.append(
        Tapback(
          type: type, sender: "me", isFromMe: true, date: Date(), messageGUID: messageGUID))
    }

    // Create updated message with new tapbacks
    let updatedMessage = Message(
      id: message.id,
      guid: message.guid,
      text: message.text,
      date: message.date,
      isFromMe: message.isFromMe,
      handleId: message.handleId,
      conversationId: message.conversationId,
      attachments: message.attachments,
      detectedCodes: message.detectedCodes,
      highlights: message.highlights,
      mentions: message.mentions,
      tapbacks: tapbacks.isEmpty ? nil : tapbacks,
      dateDelivered: message.dateDelivered,
      dateRead: message.dateRead,
      linkPreview: message.linkPreview
    )

    conversationMessages[messageIndex] = updatedMessage
    messages[conversationId] = conversationMessages

    // Send request to server
    do {
      try await bridgeService.sendTapback(type: type, messageGUID: messageGUID, action: action)
      logDebug("Tapback \(action.rawValue) sent successfully for message \(messageGUID)")
    } catch {
      // Rollback to previous tapbacks on failure
      logError("Failed to send tapback, rolling back", error: error)
      lastError = error

      if var rollbackMessages = messages[conversationId],
        let rollbackIndex = rollbackMessages.firstIndex(where: { $0.guid == messageGUID })
      {
        let rollbackTarget = rollbackMessages[rollbackIndex]
        let rolledBackMessage = Message(
          id: rollbackTarget.id,
          guid: rollbackTarget.guid,
          text: rollbackTarget.text,
          date: rollbackTarget.date,
          isFromMe: rollbackTarget.isFromMe,
          handleId: rollbackTarget.handleId,
          conversationId: rollbackTarget.conversationId,
          attachments: rollbackTarget.attachments,
          detectedCodes: rollbackTarget.detectedCodes,
          highlights: rollbackTarget.highlights,
          mentions: rollbackTarget.mentions,
          tapbacks: previousTapbacks,
          dateDelivered: rollbackTarget.dateDelivered,
          dateRead: rollbackTarget.dateRead,
          linkPreview: rollbackTarget.linkPreview
        )
        rollbackMessages[rollbackIndex] = rolledBackMessage
        messages[conversationId] = rollbackMessages
      }
    }
  }

}
