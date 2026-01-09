import Foundation

/// Detects new messages by watching chat.db for changes and querying for new messages
public actor MessageChangeDetector {
    private let database: ChatDatabaseProtocol
    private let fileWatcher: FileWatcherProtocol
    private var lastMessageId: Int64 = 0
    private var onNewMessage: ((Message, String?) async -> Void)?

    public init(database: ChatDatabaseProtocol, fileWatcher: FileWatcherProtocol) {
        self.database = database
        self.fileWatcher = fileWatcher
    }

    /// Start detecting new messages
    /// - Parameter handler: Called when a new message is detected, with the message and sender address
    public func startDetecting(handler: @escaping (Message, String?) async -> Void) async throws {
        self.onNewMessage = handler

        // Get the current latest message ID as baseline
        let recentMessages = try await database.fetchRecentConversations(limit: 1, offset: 0)
        if let lastMessage = recentMessages.first?.lastMessage {
            lastMessageId = lastMessage.id
        }

        // Start watching for file changes
        try await fileWatcher.startWatching { [weak self] in
            Task {
                await self?.checkForNewMessages()
            }
        }
    }

    /// Stop detecting messages
    public func stopDetecting() async {
        await fileWatcher.stopWatching()
        onNewMessage = nil
    }

    // MARK: - Private Methods

    private func checkForNewMessages() async {
        do {
            let newMessages = try await fetchNewMessages()

            for (message, sender) in newMessages {
                await onNewMessage?(message, sender)

                if message.id > lastMessageId {
                    lastMessageId = message.id
                }
            }
        } catch {
            // Log error but continue watching
        }
    }

    private func fetchNewMessages() async throws -> [(Message, String?)] {
        // Fetch recent conversations to get new messages
        let conversations = try await database.fetchRecentConversations(limit: 10, offset: 0)

        var newMessages: [(Message, String?)] = []

        for conversation in conversations {
            // Get messages for this conversation
            let messages = try await database.fetchMessages(
                conversationId: conversation.id,
                limit: 10,
                offset: 0
            )

            for message in messages {
                if message.id > lastMessageId {
                    // Find sender address from participants
                    let sender = conversation.participants.first { participant in
                        participant.id == message.handleId
                    }?.address

                    newMessages.append((message, sender))
                }
            }
        }

        // Sort by ID to process in order
        return newMessages.sorted { $0.0.id < $1.0.id }
    }
}
