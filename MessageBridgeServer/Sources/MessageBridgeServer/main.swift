import ArgumentParser
import Foundation

@main
struct MessageBridgeServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "MessageBridgeServer",
        abstract: "A bridge server for accessing iMessages remotely"
    )

    @Flag(name: .long, help: "Test database connectivity and print recent conversations")
    var testDb = false

    @Option(name: .shortAndLong, help: "Port to run the server on")
    var port: Int = 8080

    mutating func run() async throws {
        if testDb {
            try await runDatabaseTest()
        } else {
            try await startServer()
        }
    }

    private func runDatabaseTest() async throws {
        print("Testing Messages database connectivity...\n")

        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("✗ Database not found at: \(dbPath)")
            print("  Make sure Messages.app has been used on this Mac.")
            throw ExitCode.failure
        }

        print("✓ Database found at: \(dbPath)")

        do {
            let database = try ChatDatabase(path: dbPath)
            let stats = try await database.getStats()

            print("✓ Connected to Messages database")
            print("✓ Found \(stats.conversationCount) conversations")
            print("✓ Found \(stats.messageCount) messages")
            print("✓ Found \(stats.handleCount) contacts\n")

            let conversations = try await database.fetchRecentConversations(limit: 10)

            if conversations.isEmpty {
                print("No conversations found.")
            } else {
                print("Recent Conversations:")
                print(String(repeating: "─", count: 70))

                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated

                for conversation in conversations {
                    let displayName = conversation.displayName ?? conversation.participants.first?.address ?? "Unknown"
                    let preview = conversation.lastMessage?.text?.prefix(30) ?? "(no message)"
                    let dateStr = conversation.lastMessage.map {
                        formatter.localizedString(for: $0.date, relativeTo: Date())
                    } ?? ""

                    print("\(displayName.padding(toLength: 20, withPad: " ", startingAt: 0)) │ \(preview.padding(toLength: 30, withPad: " ", startingAt: 0)) │ \(dateStr)")
                }
                print(String(repeating: "─", count: 70))
            }

        } catch {
            print("✗ Failed to access database: \(error.localizedDescription)")
            print("\n  This usually means Terminal needs Full Disk Access.")
            print("  Go to: System Settings → Privacy & Security → Full Disk Access")
            print("  Add Terminal (or your terminal app) to the list.")
            throw ExitCode.failure
        }
    }

    private func startServer() async throws {
        print("Starting MessageBridge server on port \(port)...")
        print("Server implementation coming in Milestone 2")
        // TODO: Implement Vapor server in Milestone 2
    }
}
