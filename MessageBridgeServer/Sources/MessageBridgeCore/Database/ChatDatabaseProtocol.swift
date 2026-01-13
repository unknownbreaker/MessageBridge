import Foundation

/// Protocol for database access, enabling dependency injection and testing
public protocol ChatDatabaseProtocol: Sendable {
    func fetchRecentConversations(limit: Int, offset: Int) async throws -> [Conversation]
    func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message]
    func searchMessages(query: String, limit: Int) async throws -> [Message]
    func fetchAttachment(id: Int64) async throws -> (attachment: Attachment, filePath: String)?
}
