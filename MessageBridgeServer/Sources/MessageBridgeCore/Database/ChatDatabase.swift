import Foundation
import GRDB

/// Provides read-only access to the macOS Messages database (chat.db)
public actor ChatDatabase {
    private let dbPool: DatabasePool

    public struct Stats {
        public let conversationCount: Int
        public let messageCount: Int
        public let handleCount: Int
    }

    public init(path: String) throws {
        // Open in read-only mode - we never write to chat.db
        var config = Configuration()
        config.readonly = true
        // WAL mode checkpoint can fail in readonly, that's OK
        config.defaultTransactionKind = .deferred

        self.dbPool = try DatabasePool(path: path, configuration: config)
    }

    // MARK: - Stats

    public func getStats() throws -> Stats {
        try dbPool.read { db in
            let conversationCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat") ?? 0
            let messageCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM message") ?? 0
            let handleCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM handle") ?? 0
            return Stats(
                conversationCount: conversationCount,
                messageCount: messageCount,
                handleCount: handleCount
            )
        }
    }

    // MARK: - Conversations

    public func fetchRecentConversations(limit: Int = 50, offset: Int = 0) throws -> [Conversation] {
        try dbPool.read { db in
            // Get chats with their most recent message
            let sql = """
                SELECT
                    c.ROWID as chat_id,
                    c.guid as chat_guid,
                    c.chat_identifier,
                    c.display_name,
                    c.style as chat_style,
                    m.ROWID as message_id,
                    m.guid as message_guid,
                    m.text,
                    m.date as message_date,
                    m.is_from_me,
                    m.handle_id
                FROM chat c
                LEFT JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
                LEFT JOIN message m ON cmj.message_id = m.ROWID
                WHERE m.ROWID = (
                    SELECT MAX(m2.ROWID)
                    FROM message m2
                    JOIN chat_message_join cmj2 ON m2.ROWID = cmj2.message_id
                    WHERE cmj2.chat_id = c.ROWID
                )
                ORDER BY m.date DESC
                LIMIT ? OFFSET ?
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [limit, offset])

            return try rows.map { row in
                try conversationFromRow(row, db: db)
            }
        }
    }

    // MARK: - Messages

    public func fetchMessages(conversationId: String, limit: Int = 50, offset: Int = 0) throws -> [Message] {
        try dbPool.read { db in
            let sql = """
                SELECT
                    m.ROWID as id,
                    m.guid,
                    m.text,
                    m.date,
                    m.is_from_me,
                    m.handle_id
                FROM message m
                JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                JOIN chat c ON cmj.chat_id = c.ROWID
                WHERE c.chat_identifier = ?
                ORDER BY m.date DESC
                LIMIT ? OFFSET ?
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [conversationId, limit, offset])

            return rows.map { row in
                Message(
                    id: row["id"],
                    guid: row["guid"],
                    text: row["text"],
                    date: Message.dateFromAppleTimestamp(row["date"]),
                    isFromMe: (row["is_from_me"] as Int?) == 1,
                    handleId: row["handle_id"],
                    conversationId: conversationId
                )
            }
        }
    }

    // MARK: - Handles

    public func fetchAllHandles() throws -> [Handle] {
        try dbPool.read { db in
            let sql = """
                SELECT ROWID as id, id as address, service
                FROM handle
                ORDER BY ROWID
                """
            let rows = try Row.fetchAll(db, sql: sql)

            return rows.map { row in
                Handle(
                    id: row["id"],
                    address: row["address"],
                    service: row["service"] ?? "iMessage"
                )
            }
        }
    }

    // MARK: - Private Helpers

    private func conversationFromRow(_ row: Row, db: Database) throws -> Conversation {
        let chatId: Int64 = row["chat_id"]
        let chatIdentifier: String = row["chat_identifier"]

        let participants = try fetchHandlesForChat(db: db, chatId: chatId)
        let lastMessage = messageFromRow(row, conversationId: chatIdentifier)

        let chatStyle: Int? = row["chat_style"]
        let isGroup = chatStyle == 43

        return Conversation(
            id: chatIdentifier,
            guid: row["chat_guid"],
            displayName: row["display_name"],
            participants: participants,
            lastMessage: lastMessage,
            isGroup: isGroup
        )
    }

    private func messageFromRow(_ row: Row, conversationId: String) -> Message? {
        guard let messageId: Int64 = row["message_id"],
              let messageGuid: String = row["message_guid"],
              let messageDate: Int64 = row["message_date"] else {
            return nil
        }

        return Message(
            id: messageId,
            guid: messageGuid,
            text: row["text"],
            date: Message.dateFromAppleTimestamp(messageDate),
            isFromMe: (row["is_from_me"] as Int?) == 1,
            handleId: row["handle_id"],
            conversationId: conversationId
        )
    }

    private func fetchHandlesForChat(db: Database, chatId: Int64) throws -> [Handle] {
        let sql = """
            SELECT h.ROWID as id, h.id as address, h.service
            FROM handle h
            JOIN chat_handle_join chj ON h.ROWID = chj.handle_id
            WHERE chj.chat_id = ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: [chatId])

        return rows.map { row in
            Handle(
                id: row["id"],
                address: row["address"],
                service: row["service"] ?? "iMessage"
            )
        }
    }
}
