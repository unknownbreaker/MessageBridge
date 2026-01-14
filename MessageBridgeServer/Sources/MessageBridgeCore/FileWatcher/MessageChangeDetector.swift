import Foundation

/// Detects new messages by watching chat.db for changes and querying for new messages
public actor MessageChangeDetector {
    private let database: ChatDatabaseProtocol
    private let fileWatcher: FileWatcherProtocol
    private var lastMessageId: Int64 = 0
    private var onNewMessage: ((Message, String?) async -> Void)?
    private var pollTimer: Task<Void, Never>?
    private let pollInterval: TimeInterval = 0.5 // Poll every 500ms as backup

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
            serverLog("Starting with baseline message ID \(lastMessageId)")
        } else {
            serverLog("Starting with no existing messages")
        }

        // Start watching for file changes
        try await fileWatcher.startWatching { [weak self] in
            Task {
                await self?.checkForNewMessages()
            }
        }

        // Start backup polling timer (FSEvents can be slow/unreliable)
        startPolling()
        serverLog("Now watching for new messages (with \(Int(pollInterval * 1000))ms backup polling)")
    }

    private func startPolling() {
        pollTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(500_000_000)) // 500ms
                await self?.checkForNewMessages()
            }
        }
    }

    /// Stop detecting messages
    public func stopDetecting() async {
        pollTimer?.cancel()
        pollTimer = nil
        await fileWatcher.stopWatching()
        onNewMessage = nil
    }

    // MARK: - Private Methods

    private func checkForNewMessages() async {
        let startTime = Date()
        do {
            // Use fast direct query instead of fetching full conversations
            let newMessages = try database.fetchMessagesNewerThan(id: lastMessageId, limit: 20)

            // Only log when there are new messages (avoid log spam from polling)
            if !newMessages.isEmpty {
                let queryTime = Date().timeIntervalSince(startTime) * 1000
                serverLog("Found \(newMessages.count) new message(s) in \(String(format: "%.1f", queryTime))ms")

                for (message, _, senderAddress) in newMessages {
                    let messageAge = Date().timeIntervalSince(message.date) * 1000
                    serverLog("Broadcasting message ID \(message.id) from \(senderAddress ?? "unknown"), age: \(Int(messageAge))ms")

                    // Use sender address directly (contact lookup would add latency)
                    await onNewMessage?(message, senderAddress)

                    if message.id > lastMessageId {
                        lastMessageId = message.id
                    }
                }
            }
        } catch {
            serverLogError("Error checking for new messages: \(error)")
        }
    }
}
