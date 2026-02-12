import Foundation
import Vapor

/// Server status for UI display
public enum ServerStatus: Sendable, Equatable {
  case stopped
  case starting
  case running(port: Int)
  case error(String)

  public var isRunning: Bool {
    if case .running = self { return true }
    return false
  }

  public var displayText: String {
    switch self {
    case .stopped:
      return "Stopped"
    case .starting:
      return "Starting..."
    case .running(let port):
      return "Running on port \(port)"
    case .error(let message):
      return "Error: \(message)"
    }
  }
}

/// Manages the Vapor server lifecycle
public actor ServerManager {
  private var application: Application?
  private var database: ChatDatabase?
  private var messageDetector: MessageChangeDetector?
  private var webSocketManager: WebSocketManager?
  private var pinnedWatcher: PinnedConversationWatcher?

  private(set) public var status: ServerStatus = .stopped
  private(set) public var port: Int = 8080

  public init() {}

  /// Start the server with the given configuration
  public func start(port: Int = 8080, apiKey: String) async throws {
    guard !status.isRunning else {
      throw ServerError.alreadyRunning
    }

    self.port = port
    status = .starting

    do {
      // Initialize database
      let dbPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db")
        .path

      guard FileManager.default.fileExists(atPath: dbPath) else {
        throw ServerError.databaseNotFound
      }

      let database = try ChatDatabase(path: dbPath)
      self.database = database

      // Initialize components
      let messageSender = AppleScriptMessageSender()
      let webSocketManager = WebSocketManager()
      self.webSocketManager = webSocketManager

      // Set up file watcher
      let fileWatcher = FSEventsFileWatcher(path: dbPath)
      let messageDetector = MessageChangeDetector(database: database, fileWatcher: fileWatcher)
      self.messageDetector = messageDetector

      // Set up pinned conversation watcher
      let pinnedWatcher = PinnedConversationWatcher(database: database)
      self.pinnedWatcher = pinnedWatcher

      // Create and configure Vapor application
      var env = Environment.development
      env.arguments = ["serve"]
      let app = try await Application.make(env)
      app.http.server.configuration.port = port
      app.http.server.configuration.hostname = "0.0.0.0"

      // Configure routes
      try configureRoutes(
        app,
        database: database,
        messageSender: messageSender,
        apiKey: apiKey,
        webSocketManager: webSocketManager,
        pinnedWatcher: pinnedWatcher
      )

      self.application = app

      // Configure tapback callbacks
      await messageDetector.setTapbackCallbacks(
        onAdded: { [weak webSocketManager] tapback, conversationId in
          await webSocketManager?.broadcastTapbackAdded(tapback, conversationId: conversationId)
        },
        onRemoved: { [weak webSocketManager] tapback, conversationId in
          await webSocketManager?.broadcastTapbackRemoved(tapback, conversationId: conversationId)
        }
      )

      // Start message detection
      try await messageDetector.startDetecting { [weak webSocketManager] message, sender in
        await webSocketManager?.broadcastNewMessage(message, sender: sender)
      }

      // Start pinned conversation detection
      await pinnedWatcher.startWatching { [weak webSocketManager] pins in
        await webSocketManager?.broadcastPinnedConversationsChanged(pins)
      }

      // Start server in background task
      Task {
        do {
          try await app.execute()
        } catch {
          print("[ServerManager] app.execute() failed: \(error)")
          await self.handleServerError(error)
        }
      }

      // Give server a moment to start
      try await Task.sleep(for: .milliseconds(500))

      status = .running(port: port)

    } catch {
      status = .error(error.localizedDescription)
      throw error
    }
  }

  /// Stop the server
  public func stop() async {
    guard status.isRunning else { return }

    status = .stopped

    // Stop message detection
    await messageDetector?.stopDetecting()
    messageDetector = nil

    // Stop pinned conversation detection
    await pinnedWatcher?.stopWatching()
    pinnedWatcher = nil

    // Shutdown Vapor application
    if let app = application {
      try? await app.asyncShutdown()
    }
    application = nil
    database = nil
    webSocketManager = nil
  }

  /// Restart the server with new configuration
  public func restart(port: Int? = nil, apiKey: String) async throws {
    let newPort = port ?? self.port
    await stop()
    try await Task.sleep(for: .milliseconds(500))
    try await start(port: newPort, apiKey: apiKey)
  }

  /// Handle server errors
  private func handleServerError(_ error: Error) async {
    status = .error(error.localizedDescription)
    if let app = application {
      try? await app.asyncShutdown()
    }
    application = nil
  }

  /// Get database stats
  public func getDatabaseStats() async throws -> ChatDatabase.Stats {
    guard let database = database else {
      throw ServerError.notRunning
    }
    return try await database.getStats()
  }
}

/// Server-related errors
public enum ServerError: LocalizedError {
  case alreadyRunning
  case notRunning
  case databaseNotFound
  case fullDiskAccessRequired

  public var errorDescription: String? {
    switch self {
    case .alreadyRunning:
      return "Server is already running"
    case .notRunning:
      return "Server is not running"
    case .databaseNotFound:
      return "Messages database not found"
    case .fullDiskAccessRequired:
      return "Full Disk Access permission required"
    }
  }
}
