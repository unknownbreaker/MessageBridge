import XCTest
@testable import MessageBridgeClientCore

final class LoggerTests: XCTestCase {

    var tempLogDirectory: URL!
    var logManager: LogManager!

    override func setUp() async throws {
        // Create temp directory for test logs
        tempLogDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageBridgeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempLogDirectory, withIntermediateDirectories: true)
        logManager = LogManager(logDirectory: tempLogDirectory)
    }

    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempLogDirectory)
    }

    // MARK: - Log Entry Tests

    func testLogEntry_containsTimestamp() {
        let entry = LogEntry(
            level: .error,
            message: "Test message",
            file: "TestFile.swift",
            function: "testFunction()",
            line: 42
        )

        XCTAssertNotNil(entry.timestamp)
    }

    func testLogEntry_containsSourceLocation() {
        let entry = LogEntry(
            level: .error,
            message: "Test message",
            file: "/path/to/TestFile.swift",
            function: "testFunction()",
            line: 42
        )

        XCTAssertEqual(entry.fileName, "TestFile.swift")
        XCTAssertEqual(entry.function, "testFunction()")
        XCTAssertEqual(entry.line, 42)
    }

    func testLogEntry_formattedOutput_includesAllInfo() {
        let entry = LogEntry(
            level: .error,
            message: "Something went wrong",
            file: "/path/to/MyFile.swift",
            function: "doSomething()",
            line: 123
        )

        let formatted = entry.formatted
        XCTAssertTrue(formatted.contains("[ERROR]"))
        XCTAssertTrue(formatted.contains("MyFile.swift:123"))
        XCTAssertTrue(formatted.contains("doSomething()"))
        XCTAssertTrue(formatted.contains("Something went wrong"))
    }

    func testLogEntry_levelColors() {
        XCTAssertEqual(LogLevel.debug.emoji, "🔍")
        XCTAssertEqual(LogLevel.info.emoji, "ℹ️")
        XCTAssertEqual(LogLevel.warning.emoji, "⚠️")
        XCTAssertEqual(LogLevel.error.emoji, "❌")
    }

    // MARK: - LogManager Write Tests

    func testLogManager_writesLogToFile() async throws {
        let entry = LogEntry(
            level: .error,
            message: "Test error",
            file: "Test.swift",
            function: "test()",
            line: 1
        )

        await logManager.write(entry)

        let logs = await logManager.readLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message, "Test error")
    }

    func testLogManager_appendsMultipleLogs() async throws {
        for i in 1...3 {
            let entry = LogEntry(
                level: .info,
                message: "Log \(i)",
                file: "Test.swift",
                function: "test()",
                line: i
            )
            await logManager.write(entry)
        }

        let logs = await logManager.readLogs()
        XCTAssertEqual(logs.count, 3)
    }

    func testLogManager_preservesLogLevel() async throws {
        let entry = LogEntry(
            level: .warning,
            message: "Warning message",
            file: "Test.swift",
            function: "test()",
            line: 1
        )

        await logManager.write(entry)

        let logs = await logManager.readLogs()
        XCTAssertEqual(logs.first?.level, .warning)
    }

    // MARK: - Log Cleanup Tests

    func testLogManager_cleansUpOldLogs() async throws {
        // Create an old log entry (simulated by setting old timestamp)
        let oldEntry = LogEntry(
            level: .error,
            message: "Old error",
            file: "Test.swift",
            function: "test()",
            line: 1,
            timestamp: Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        )

        let recentEntry = LogEntry(
            level: .error,
            message: "Recent error",
            file: "Test.swift",
            function: "test()",
            line: 2,
            timestamp: Date() // Now
        )

        await logManager.write(oldEntry)
        await logManager.write(recentEntry)

        // Clean up logs older than 7 days
        await logManager.cleanupOldLogs(olderThan: 7 * 24 * 60 * 60)

        let logs = await logManager.readLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message, "Recent error")
    }

    func testLogManager_keepsRecentLogs() async throws {
        let recentEntry = LogEntry(
            level: .error,
            message: "Recent error",
            file: "Test.swift",
            function: "test()",
            line: 1,
            timestamp: Date().addingTimeInterval(-2 * 24 * 60 * 60) // 2 days ago
        )

        await logManager.write(recentEntry)
        await logManager.cleanupOldLogs(olderThan: 7 * 24 * 60 * 60)

        let logs = await logManager.readLogs()
        XCTAssertEqual(logs.count, 1)
    }

    // MARK: - Log Filtering Tests

    func testLogManager_filtersByLevel() async throws {
        let entries = [
            LogEntry(level: .debug, message: "Debug", file: "T.swift", function: "t()", line: 1),
            LogEntry(level: .info, message: "Info", file: "T.swift", function: "t()", line: 2),
            LogEntry(level: .warning, message: "Warning", file: "T.swift", function: "t()", line: 3),
            LogEntry(level: .error, message: "Error", file: "T.swift", function: "t()", line: 4)
        ]

        for entry in entries {
            await logManager.write(entry)
        }

        let errorLogs = await logManager.readLogs(minimumLevel: .error)
        XCTAssertEqual(errorLogs.count, 1)

        let warningAndAbove = await logManager.readLogs(minimumLevel: .warning)
        XCTAssertEqual(warningAndAbove.count, 2)
    }

    // MARK: - Clear Logs Tests

    func testLogManager_clearAllLogs() async throws {
        let entry = LogEntry(
            level: .error,
            message: "Test",
            file: "Test.swift",
            function: "test()",
            line: 1
        )

        await logManager.write(entry)
        await logManager.clearAllLogs()

        let logs = await logManager.readLogs()
        XCTAssertTrue(logs.isEmpty)
    }
}

// MARK: - Logger Convenience Tests

final class AppLoggerTests: XCTestCase {

    func testLogger_capturesSourceLocation() {
        let entry = AppLogger.createEntry(
            level: .error,
            message: "Test",
            file: #file,
            function: #function,
            line: #line
        )

        XCTAssertTrue(entry.fileName.contains("LoggerTests.swift"))
        XCTAssertTrue(entry.function.contains("testLogger_capturesSourceLocation"))
    }
}
