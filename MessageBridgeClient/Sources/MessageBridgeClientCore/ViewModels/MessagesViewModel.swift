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

    private let bridgeService: any BridgeServiceProtocol
    private let notificationManager: NotificationManager

    public init(
        bridgeService: any BridgeServiceProtocol = BridgeConnection(),
        notificationManager: NotificationManager = NotificationManager()
    ) {
        self.bridgeService = bridgeService
        self.notificationManager = notificationManager
        // Load placeholder data for now
        loadPlaceholderData()
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

    private func startWebSocket() async {
        do {
            try await bridgeService.startWebSocket { [weak self] message, sender in
                Task { @MainActor [weak self] in
                    await self?.handleNewMessage(message, sender: sender)
                }
            }
            logInfo("WebSocket connection started")
        } catch {
            logError("Failed to start WebSocket", error: error)
        }
    }

    private func handleNewMessage(_ message: Message, sender: String) async {
        // Add message to the conversation
        let conversationId = message.conversationId
        messages[conversationId, default: []].insert(message, at: 0)

        // Update conversation's last message
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            var updatedConversation = conversations[index]
            updatedConversation = Conversation(
                id: updatedConversation.id,
                guid: updatedConversation.guid,
                displayName: updatedConversation.displayName,
                participants: updatedConversation.participants,
                lastMessage: message,
                isGroup: updatedConversation.isGroup
            )
            conversations[index] = updatedConversation
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

    public func selectConversation(_ conversationId: String?) {
        selectedConversationId = conversationId
        // Clear notifications for this conversation when selected
        if let id = conversationId {
            Task {
                await notificationManager.clearNotifications(for: id)
            }
        }
    }

    public func loadConversations() async {
        do {
            conversations = try await bridgeService.fetchConversations(limit: 50, offset: 0)
            logDebug("Loaded \(conversations.count) conversations")
        } catch {
            logError("Failed to load conversations", error: error)
        }
    }

    public func loadMessages(for conversationId: String) async {
        do {
            let msgs = try await bridgeService.fetchMessages(conversationId: conversationId, limit: 50, offset: 0)
            messages[conversationId] = msgs
            logDebug("Loaded \(msgs.count) messages for conversation \(conversationId)")
        } catch {
            logError("Failed to load messages for conversation \(conversationId)", error: error)
        }
    }

    public func sendMessage(_ text: String, toConversation conversation: Conversation) async {
        // Clear any previous error
        lastError = nil

        // Get recipient address from first participant (for group chats, server handles routing)
        guard let recipient = conversation.participants.first?.address else {
            lastError = BridgeError.sendFailed
            return
        }

        let conversationId = conversation.id

        // Optimistic UI update: show message immediately
        let optimisticMessage = Message(
            id: Int64.random(in: Int64.min..<0), // Negative ID to indicate pending
            guid: UUID().uuidString,
            text: text,
            date: Date(),
            isFromMe: true,
            handleId: nil,
            conversationId: conversationId
        )
        messages[conversationId, default: []].insert(optimisticMessage, at: 0)

        do {
            let sentMessage = try await bridgeService.sendMessage(text: text, to: recipient)
            // Replace optimistic message with real one
            if let index = messages[conversationId]?.firstIndex(where: { $0.guid == optimisticMessage.guid }) {
                messages[conversationId]?[index] = sentMessage
            }
        } catch {
            // Remove optimistic message on failure
            messages[conversationId]?.removeAll { $0.guid == optimisticMessage.guid }
            lastError = error
            logError("Failed to send message to \(recipient)", error: error)
        }
    }

    // MARK: - Placeholder Data (for development)

    private func loadPlaceholderData() {
        conversations = [
            Conversation(
                id: "chat-1",
                guid: "guid-1",
                displayName: "John Doe",
                participants: [Handle(id: 1, address: "+1 (555) 123-4567", service: "iMessage")],
                lastMessage: Message(
                    id: 1,
                    guid: "msg-1",
                    text: "See you tomorrow!",
                    date: Date().addingTimeInterval(-3600),
                    isFromMe: false,
                    handleId: 1,
                    conversationId: "chat-1"
                ),
                isGroup: false
            ),
            Conversation(
                id: "chat-2",
                guid: "guid-2",
                displayName: "Jane Smith",
                participants: [Handle(id: 2, address: "+1 (555) 987-6543", service: "iMessage")],
                lastMessage: Message(
                    id: 2,
                    guid: "msg-2",
                    text: "Got it, thanks!",
                    date: Date().addingTimeInterval(-7200),
                    isFromMe: true,
                    handleId: nil,
                    conversationId: "chat-2"
                ),
                isGroup: false
            ),
            Conversation(
                id: "chat-3",
                guid: "guid-3",
                displayName: "Work Team",
                participants: [
                    Handle(id: 3, address: "+1 (555) 111-2222", service: "iMessage"),
                    Handle(id: 4, address: "+1 (555) 333-4444", service: "iMessage")
                ],
                lastMessage: Message(
                    id: 3,
                    guid: "msg-3",
                    text: "Meeting at 3pm",
                    date: Date().addingTimeInterval(-14400),
                    isFromMe: false,
                    handleId: 3,
                    conversationId: "chat-3"
                ),
                isGroup: true
            )
        ]

        // Add some sample messages
        messages["chat-1"] = [
            Message(id: 1, guid: "msg-1", text: "See you tomorrow!", date: Date().addingTimeInterval(-3600), isFromMe: false, handleId: 1, conversationId: "chat-1"),
            Message(id: 4, guid: "msg-4", text: "Sounds good!", date: Date().addingTimeInterval(-3700), isFromMe: true, handleId: nil, conversationId: "chat-1"),
            Message(id: 5, guid: "msg-5", text: "Want to grab lunch tomorrow?", date: Date().addingTimeInterval(-3800), isFromMe: false, handleId: 1, conversationId: "chat-1"),
            Message(id: 6, guid: "msg-6", text: "Hey! How are you?", date: Date().addingTimeInterval(-86400), isFromMe: false, handleId: 1, conversationId: "chat-1"),
        ]
    }
}
