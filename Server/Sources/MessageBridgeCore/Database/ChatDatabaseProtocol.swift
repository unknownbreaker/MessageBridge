import Foundation

/// Protocol for database access, enabling dependency injection and testing
public protocol ChatDatabaseProtocol: Sendable {
  func fetchRecentConversations(limit: Int, offset: Int) async throws -> [Conversation]
  func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message]
  func fetchMessagesNewerThan(id: Int64, limit: Int) throws -> [(
    message: Message, conversationId: String, senderAddress: String?
  )]
  func searchMessages(query: String, limit: Int) async throws -> [Message]
  func fetchAttachment(id: Int64) async throws -> (attachment: Attachment, filePath: String)?
  func markConversationAsRead(conversationId: String) async throws -> SyncResult

  /// Fetch tapback rows (associated_message_type 2000-3005) newer than a given ROWID.
  /// Returns parsed tapbacks with their ROWID, target message's conversation ID, and whether it's a removal.
  func fetchTapbacksNewerThan(id: Int64, limit: Int) throws -> [(
    rowId: Int64, tapback: Tapback, conversationId: String, isRemoval: Bool
  )]

  /// Look up a message's text by its GUID (used by reply-send pipeline to find original message text).
  func fetchMessageText(byGuid guid: String) async throws -> String?
}
