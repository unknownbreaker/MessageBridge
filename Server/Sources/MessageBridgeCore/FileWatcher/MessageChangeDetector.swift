import Foundation

/// Detects new messages by watching chat.db for changes and querying for new messages
public actor MessageChangeDetector {
  private let database: ChatDatabaseProtocol
  private let fileWatcher: FileWatcherProtocol
  private var lastMessageId: Int64 = 0
  private var lastTapbackId: Int64 = 0
  private var onNewMessage: ((Message, String?) async -> Void)?
  private var pollTimer: Task<Void, Never>?
  private let pollInterval: TimeInterval = 0.5  // Poll every 500ms as backup

  /// Called when a tapback is added to a message.
  /// Parameters: (tapback, conversationId)
  public var onTapbackAdded: ((Tapback, String) async -> Void)?

  /// Called when a tapback is removed from a message.
  /// Parameters: (tapback, conversationId)
  public var onTapbackRemoved: ((Tapback, String) async -> Void)?

  public init(database: ChatDatabaseProtocol, fileWatcher: FileWatcherProtocol) {
    self.database = database
    self.fileWatcher = fileWatcher
  }

  /// Set the tapback callback handlers
  /// - Parameters:
  ///   - onAdded: Called when a tapback is added (tapback, conversationId)
  ///   - onRemoved: Called when a tapback is removed (tapback, conversationId)
  public func setTapbackCallbacks(
    onAdded: @escaping (Tapback, String) async -> Void,
    onRemoved: @escaping (Tapback, String) async -> Void
  ) {
    self.onTapbackAdded = onAdded
    self.onTapbackRemoved = onRemoved
  }

  /// Start detecting new messages
  /// - Parameter handler: Called when a new message is detected, with the message and sender address
  public func startDetecting(handler: @escaping (Message, String?) async -> Void) async throws {
    self.onNewMessage = handler

    // Get the current latest message ID as baseline
    let recentMessages = try await database.fetchRecentConversations(limit: 1, offset: 0)
    if let lastMessage = recentMessages.first?.lastMessage {
      lastMessageId = lastMessage.id
      lastTapbackId = lastMessage.id  // Tapbacks are also in message table, use same baseline
      serverLog("Starting with baseline message ID \(lastMessageId)")
    } else {
      serverLog("Starting with no existing messages")
    }

    // Start watching for file changes
    try await fileWatcher.startWatching { [weak self] in
      Task {
        await self?.checkForNewMessages()
        await self?.checkForNewTapbacks()
      }
    }

    // Start backup polling timer (FSEvents can be slow/unreliable)
    startPolling()
    serverLog(
      "Now watching for new messages and tapbacks (with \(Int(pollInterval * 1000))ms backup polling)"
    )
  }

  private func startPolling() {
    pollTimer = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(500_000_000))  // 500ms
        await self?.checkForNewMessages()
        await self?.checkForNewTapbacks()
      }
    }
  }

  /// Stop detecting messages
  public func stopDetecting() async {
    pollTimer?.cancel()
    pollTimer = nil
    await fileWatcher.stopWatching()
    onNewMessage = nil
    onTapbackAdded = nil
    onTapbackRemoved = nil
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
        serverLog(
          "Found \(newMessages.count) new message(s) in \(String(format: "%.1f", queryTime))ms")

        for (message, _, senderAddress) in newMessages {
          let messageAge = Date().timeIntervalSince(message.date) * 1000
          serverLog(
            "Broadcasting message ID \(message.id) from \(senderAddress ?? "unknown"), age: \(Int(messageAge))ms"
          )

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

  private func checkForNewTapbacks() async {
    // Skip if no callbacks are registered
    guard onTapbackAdded != nil || onTapbackRemoved != nil else {
      return
    }

    let startTime = Date()
    do {
      let newTapbacks = try database.fetchTapbacksNewerThan(id: lastTapbackId, limit: 20)

      // Only log when there are new tapbacks (avoid log spam from polling)
      if !newTapbacks.isEmpty {
        let queryTime = Date().timeIntervalSince(startTime) * 1000
        serverLog(
          "Found \(newTapbacks.count) new tapback(s) in \(String(format: "%.1f", queryTime))ms")

        for (rowId, tapback, conversationId, isRemoval) in newTapbacks {
          let tapbackAge = Date().timeIntervalSince(tapback.date) * 1000
          let action = isRemoval ? "removed" : "added"
          serverLog(
            "Broadcasting tapback \(action): \(tapback.type.emoji) on message \(tapback.messageGUID), age: \(Int(tapbackAge))ms"
          )

          if isRemoval {
            await onTapbackRemoved?(tapback, conversationId)
          } else {
            await onTapbackAdded?(tapback, conversationId)
          }

          // Update lastTapbackId to track which tapbacks we've processed
          if rowId > lastTapbackId {
            lastTapbackId = rowId
          }
        }
      }
    } catch {
      serverLogError("Error checking for new tapbacks: \(error)")
    }
  }
}
