import Foundation
import GRDB

/// Provides read-only access to the macOS Messages database (chat.db)
public actor ChatDatabase: ChatDatabaseProtocol {
    private nonisolated let dbPool: DatabasePool
    private let contactManager: ContactManager

    public struct Stats {
        public let conversationCount: Int
        public let messageCount: Int
        public let handleCount: Int
    }

    public init(path: String, contactManager: ContactManager = .shared) throws {
        // Open in read-only mode - we never write to chat.db
        var config = Configuration()
        config.readonly = true
        // WAL mode checkpoint can fail in readonly, that's OK
        config.defaultTransactionKind = .deferred

        self.dbPool = try DatabasePool(path: path, configuration: config)
        self.contactManager = contactManager
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

    public func fetchRecentConversations(limit: Int = 50, offset: Int = 0) async throws -> [Conversation] {
        // First fetch conversations from database (synchronously)
        let conversations = try fetchRecentConversationsFromDB(limit: limit, offset: offset)

        // Collect all unique addresses from participants
        var allAddresses = Set<String>()
        for conversation in conversations {
            for participant in conversation.participants {
                allAddresses.insert(participant.address)
            }
        }

        // Look up contact info (name and photo) for all addresses at once
        let contactInfo = await contactManager.lookupContactInfo(for: Array(allAddresses))

        // Enrich conversations with contact names and photos
        return conversations.map { conversation in
            let enrichedParticipants = conversation.participants.map { handle in
                let info = contactInfo[handle.address]
                return Handle(
                    id: handle.id,
                    address: handle.address,
                    service: handle.service,
                    contactName: info?.name,
                    photoBase64: info?.photoData?.base64EncodedString()
                )
            }
            return Conversation(
                id: conversation.id,
                guid: conversation.guid,
                displayName: conversation.displayName,
                participants: enrichedParticipants,
                lastMessage: conversation.lastMessage,
                isGroup: conversation.isGroup
            )
        }
    }

    private nonisolated func fetchRecentConversationsFromDB(limit: Int, offset: Int) throws -> [Conversation] {
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
                    m.attributedBody,
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
                try self.conversationFromRow(row, db: db)
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
                    m.attributedBody,
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
                let text: String? = row["text"]
                let attributedBody: Data? = row["attributedBody"]

                // Use text if available, otherwise try to extract from attributedBody
                let messageText: String?
                if let text = text, !text.isEmpty {
                    messageText = text
                } else if let attributedBody = attributedBody {
                    messageText = Message.extractTextFromAttributedBody(attributedBody)
                } else {
                    messageText = nil
                }

                return Message(
                    id: row["id"],
                    guid: row["guid"],
                    text: messageText,
                    date: Message.dateFromAppleTimestamp(row["date"]),
                    isFromMe: (row["is_from_me"] as Int?) == 1,
                    handleId: row["handle_id"],
                    conversationId: conversationId
                )
            }
        }
    }

    // MARK: - Search

    public func searchMessages(query: String, limit: Int = 50) throws -> [Message] {
        try dbPool.read { db in
            let sql = """
                SELECT
                    m.ROWID as id,
                    m.guid,
                    m.text,
                    m.attributedBody,
                    m.date,
                    m.is_from_me,
                    m.handle_id,
                    c.chat_identifier as conversation_id
                FROM message m
                JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                JOIN chat c ON cmj.chat_id = c.ROWID
                WHERE m.text LIKE '%' || ? || '%'
                ORDER BY m.date DESC
                LIMIT ?
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [query, limit])

            return rows.compactMap { row -> Message? in
                guard let conversationId: String = row["conversation_id"] else {
                    return nil
                }

                let text: String? = row["text"]
                let attributedBody: Data? = row["attributedBody"]

                // Use text if available, otherwise try to extract from attributedBody
                let messageText: String?
                if let text = text, !text.isEmpty {
                    messageText = text
                } else if let attributedBody = attributedBody {
                    messageText = Message.extractTextFromAttributedBody(attributedBody)
                } else {
                    messageText = nil
                }

                return Message(
                    id: row["id"],
                    guid: row["guid"],
                    text: messageText,
                    date: Message.dateFromAppleTimestamp(row["date"]),
                    isFromMe: (row["is_from_me"] as Int?) == 1,
                    handleId: row["handle_id"],
                    conversationId: conversationId
                )
            }
        }
    }

    // MARK: - Handles

    public func fetchAllHandles() async throws -> [Handle] {
        let handles = try fetchAllHandlesFromDB()

        // Look up contact info (name and photo) for all addresses
        let addresses = handles.map { $0.address }
        let contactInfo = await contactManager.lookupContactInfo(for: addresses)

        // Enrich handles with contact names and photos
        return handles.map { handle in
            let info = contactInfo[handle.address]
            return Handle(
                id: handle.id,
                address: handle.address,
                service: handle.service,
                contactName: info?.name,
                photoBase64: info?.photoData?.base64EncodedString()
            )
        }
    }

    private nonisolated func fetchAllHandlesFromDB() throws -> [Handle] {
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

    private nonisolated func conversationFromRow(_ row: Row, db: Database) throws -> Conversation {
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

    private nonisolated func messageFromRow(_ row: Row, conversationId: String) -> Message? {
        guard let messageId: Int64 = row["message_id"],
              let messageGuid: String = row["message_guid"],
              let messageDate: Int64 = row["message_date"] else {
            return nil
        }

        let text: String? = row["text"]
        let attributedBody: Data? = row["attributedBody"]

        // Use text if available, otherwise try to extract from attributedBody
        let messageText: String?
        if let text = text, !text.isEmpty {
            messageText = text
        } else if let attributedBody = attributedBody {
            messageText = Message.extractTextFromAttributedBody(attributedBody)
        } else {
            messageText = nil
        }

        return Message(
            id: messageId,
            guid: messageGuid,
            text: messageText,
            date: Message.dateFromAppleTimestamp(messageDate),
            isFromMe: (row["is_from_me"] as Int?) == 1,
            handleId: row["handle_id"],
            conversationId: conversationId
        )
    }

    private nonisolated func fetchHandlesForChat(db: Database, chatId: Int64) throws -> [Handle] {
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
