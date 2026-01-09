import Foundation

// MARK: - Log Level

public enum LogLevel: Int, Codable, Comparable, CaseIterable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }

    public var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log Entry

public struct LogEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let file: String
    public let function: String
    public let line: Int

    public init(
        level: LogLevel,
        message: String,
        file: String,
        function: String,
        line: Int,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.file = file
        self.function = function
        self.line = line
    }

    /// Extract just the filename from the full path
    public var fileName: String {
        (file as NSString).lastPathComponent
    }

    /// Formatted log string for display and file output
    public var formatted: String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = dateFormatter.string(from: self.timestamp)

        return "\(timestamp) \(level.emoji) [\(level.label)] \(fileName):\(line) \(function) - \(message)"
    }

    /// Short format for UI display
    public var shortFormatted: String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let time = timeFormatter.string(from: timestamp)

        return "\(time) \(level.emoji) \(fileName):\(line) - \(message)"
    }
}

// MARK: - Log Manager

public actor LogManager {
    private let logDirectory: URL
    private let logFileName = "messagebridge.log"
    private let jsonLogFileName = "messagebridge-logs.json"
    private var cachedLogs: [LogEntry] = []
    private var isDirty = false

    /// Default log directory in Application Support
    public static var defaultLogDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MessageBridge/Logs")
    }

    public init(logDirectory: URL? = nil) {
        self.logDirectory = logDirectory ?? Self.defaultLogDirectory

        // Create directory if needed
        try? FileManager.default.createDirectory(at: self.logDirectory, withIntermediateDirectories: true)

        // Load existing logs
        Task {
            await loadLogs()
        }
    }

    private var logFileURL: URL {
        logDirectory.appendingPathComponent(logFileName)
    }

    private var jsonLogFileURL: URL {
        logDirectory.appendingPathComponent(jsonLogFileName)
    }

    /// Write a log entry
    public func write(_ entry: LogEntry) {
        cachedLogs.append(entry)
        isDirty = true

        // Also print to console for debugging
        print(entry.formatted)

        // Persist asynchronously
        Task {
            self.persistLogs()
        }
    }

    /// Read all logs, optionally filtered by minimum level
    public func readLogs(minimumLevel: LogLevel = .debug) -> [LogEntry] {
        cachedLogs.filter { $0.level >= minimumLevel }
    }

    /// Clean up logs older than specified time interval (in seconds)
    public func cleanupOldLogs(olderThan seconds: TimeInterval) {
        let cutoffDate = Date().addingTimeInterval(-seconds)
        cachedLogs.removeAll { $0.timestamp < cutoffDate }
        isDirty = true

        Task {
            self.persistLogs()
        }
    }

    /// Clear all logs
    public func clearAllLogs() {
        cachedLogs.removeAll()
        isDirty = true

        try? FileManager.default.removeItem(at: logFileURL)
        try? FileManager.default.removeItem(at: jsonLogFileURL)
    }

    /// Get the log file URL for sharing
    public func getLogFileURL() -> URL {
        logFileURL
    }

    // MARK: - Persistence

    private func loadLogs() {
        guard FileManager.default.fileExists(atPath: jsonLogFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: jsonLogFileURL)
            cachedLogs = try JSONDecoder().decode([LogEntry].self, from: data)
        } catch {
            print("Failed to load logs: \(error)")
        }
    }

    private func persistLogs() {
        guard isDirty else { return }

        do {
            // Write JSON for structured reading
            let jsonData = try JSONEncoder().encode(cachedLogs)
            try jsonData.write(to: jsonLogFileURL, options: .atomic)

            // Write human-readable log file
            let textContent = cachedLogs.map { $0.formatted }.joined(separator: "\n")
            try textContent.write(to: logFileURL, atomically: true, encoding: .utf8)

            isDirty = false
        } catch {
            print("Failed to persist logs: \(error)")
        }
    }
}

// MARK: - App Logger (Singleton)

public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    private let logManager: LogManager
    private let cleanupInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private var cleanupTimer: Timer?

    private init() {
        self.logManager = LogManager()
        startPeriodicCleanup()
    }

    /// Create a log entry (for testing)
    public static func createEntry(
        level: LogLevel,
        message: String,
        file: String,
        function: String,
        line: Int
    ) -> LogEntry {
        LogEntry(level: level, message: message, file: file, function: function, line: line)
    }

    // MARK: - Logging Methods

    public func debug(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    public func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    public func warning(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }

    public func error(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }

    /// Log an error with the Error object
    public func error(
        _ message: String,
        error: Error,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fullMessage = "\(message): \(error.localizedDescription)"
        log(level: .error, message: fullMessage, file: file, function: function, line: line)
    }

    private func log(level: LogLevel, message: String, file: String, function: String, line: Int) {
        let entry = LogEntry(level: level, message: message, file: file, function: function, line: line)
        Task {
            await logManager.write(entry)
        }
    }

    // MARK: - Log Access

    public func getLogs(minimumLevel: LogLevel = .debug) async -> [LogEntry] {
        await logManager.readLogs(minimumLevel: minimumLevel)
    }

    public func clearLogs() async {
        await logManager.clearAllLogs()
    }

    public func getLogFileURL() async -> URL {
        await logManager.getLogFileURL()
    }

    // MARK: - Cleanup

    private func startPeriodicCleanup() {
        // Run cleanup daily
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task {
                await self?.performCleanup()
            }
        }

        // Also run cleanup on startup
        Task {
            await performCleanup()
        }
    }

    private func performCleanup() async {
        await logManager.cleanupOldLogs(olderThan: cleanupInterval)
    }
}

// MARK: - Global Convenience Functions

/// Log a debug message
public func logDebug(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    AppLogger.shared.debug(message, file: file, function: function, line: line)
}

/// Log an info message
public func logInfo(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    AppLogger.shared.info(message, file: file, function: function, line: line)
}

/// Log a warning message
public func logWarning(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    AppLogger.shared.warning(message, file: file, function: function, line: line)
}

/// Log an error message
public func logError(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    AppLogger.shared.error(message, file: file, function: function, line: line)
}

/// Log an error with an Error object
public func logError(
    _ message: String,
    error: Error,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    AppLogger.shared.error(message, error: error, file: file, function: function, line: line)
}
