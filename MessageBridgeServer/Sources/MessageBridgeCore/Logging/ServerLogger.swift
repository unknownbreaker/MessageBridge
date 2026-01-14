import Foundation

/// Log level for server logs
public enum ServerLogLevel: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: ServerLogLevel, rhs: ServerLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A log entry from the server
public struct ServerLogEntry: Sendable {
    public let timestamp: Date
    public let level: ServerLogLevel
    public let message: String
    public let file: String
    public let function: String
    public let line: Int

    public init(timestamp: Date = Date(), level: ServerLogLevel, message: String, file: String, function: String, line: Int) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.file = (file as NSString).lastPathComponent
        self.function = function
        self.line = line
    }
}

/// Callback type for log subscribers
public typealias ServerLogHandler = @Sendable (ServerLogEntry) -> Void

/// Shared logger for server components
/// Logs to stdout and notifies subscribers
public final class ServerLogger: @unchecked Sendable {
    public static let shared = ServerLogger()

    private var handlers: [ServerLogHandler] = []
    private let lock = NSLock()

    private init() {}

    /// Subscribe to log events
    public func subscribe(_ handler: @escaping ServerLogHandler) {
        lock.lock()
        defer { lock.unlock() }
        handlers.append(handler)
    }

    /// Clear all subscribers
    public func clearSubscribers() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    /// Log a message
    public func log(_ level: ServerLogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let entry = ServerLogEntry(level: level, message: message, file: file, function: function, line: line)

        // Print to stdout
        let levelStr: String
        switch level {
        case .debug: levelStr = "DEBUG"
        case .info: levelStr = "INFO"
        case .warning: levelStr = "WARNING"
        case .error: levelStr = "ERROR"
        }
        print("[\(levelStr)] \(entry.file):\(line) - \(message)")

        // Notify subscribers
        lock.lock()
        let currentHandlers = handlers
        lock.unlock()

        for handler in currentHandlers {
            handler(entry)
        }
    }
}

// Convenience functions
public func serverLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    ServerLogger.shared.log(.info, message, file: file, function: function, line: line)
}

public func serverLogDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    ServerLogger.shared.log(.debug, message, file: file, function: function, line: line)
}

public func serverLogWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    ServerLogger.shared.log(.warning, message, file: file, function: function, line: line)
}

public func serverLogError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    ServerLogger.shared.log(.error, message, file: file, function: function, line: line)
}
