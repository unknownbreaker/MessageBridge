import Foundation
import GRDB
import AppKit

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
        // Open in read-write mode to allow marking messages as read
        // WAL mode allows concurrent reads while we write
        var config = Configuration()
        config.readonly = false
        config.defaultTransactionKind = .deferred
        // Set a busy timeout to handle contention with Messages.app
        config.busyMode = .timeout(5.0)

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

        // Enrich conversations with contact names, photos, and group photos
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

            // Look up group photo for group conversations
            var groupPhotoBase64: String? = nil
            if conversation.isGroup {
                if let photoData = lookupGroupPhoto(for: conversation.guid) {
                    groupPhotoBase64 = photoData.base64EncodedString()
                }
            }

            return Conversation(
                id: conversation.id,
                guid: conversation.guid,
                displayName: conversation.displayName,
                participants: enrichedParticipants,
                lastMessage: conversation.lastMessage,
                isGroup: conversation.isGroup,
                groupPhotoBase64: groupPhotoBase64,
                unreadCount: conversation.unreadCount
            )
        }
    }

    private nonisolated func fetchRecentConversationsFromDB(limit: Int, offset: Int) throws -> [Conversation] {
        try dbPool.read { db in
            // Get chats with their most recent message and unread count
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
                    m.handle_id,
                    (
                        SELECT COUNT(*)
                        FROM message m_unread
                        JOIN chat_message_join cmj_unread ON m_unread.ROWID = cmj_unread.message_id
                        WHERE cmj_unread.chat_id = c.ROWID
                        AND m_unread.is_read = 0
                        AND m_unread.is_from_me = 0
                    ) as unread_count
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
        return try dbPool.read { db in
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

            return try rows.map { row in
                let messageId: Int64 = row["id"]
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

                // Fetch attachments for this message
                let attachments = try self.fetchAttachmentsForMessage(db: db, messageId: messageId)

                return Message(
                    id: messageId,
                    guid: row["guid"],
                    text: messageText,
                    date: Message.dateFromAppleTimestamp(row["date"]),
                    isFromMe: (row["is_from_me"] as Int?) == 1,
                    handleId: row["handle_id"],
                    conversationId: conversationId,
                    attachments: attachments
                )
            }
        }
    }

    // MARK: - New Message Detection (Fast Path)

    /// Fetch messages newer than a given ID - optimized for real-time detection
    /// This is a fast query that skips contact lookups and photo generation
    public nonisolated func fetchMessagesNewerThan(id: Int64, limit: Int = 20) throws -> [(message: Message, conversationId: String, senderAddress: String?)] {
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
                    c.chat_identifier,
                    h.id as sender_address
                FROM message m
                JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                JOIN chat c ON cmj.chat_id = c.ROWID
                LEFT JOIN handle h ON m.handle_id = h.ROWID
                WHERE m.ROWID > ?
                ORDER BY m.ROWID ASC
                LIMIT ?
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [id, limit])

            return rows.compactMap { row -> (Message, String, String?)? in
                guard let messageId: Int64 = row["id"],
                      let guid: String = row["guid"],
                      let conversationId: String = row["chat_identifier"] else {
                    return nil
                }

                let text: String? = row["text"]
                let attributedBody: Data? = row["attributedBody"]

                let messageText: String?
                if let text = text, !text.isEmpty {
                    messageText = text
                } else if let attributedBody = attributedBody {
                    messageText = Message.extractTextFromAttributedBody(attributedBody)
                } else {
                    messageText = nil
                }

                let message = Message(
                    id: messageId,
                    guid: guid,
                    text: messageText,
                    date: Message.dateFromAppleTimestamp(row["date"] ?? 0),
                    isFromMe: (row["is_from_me"] as Int?) == 1,
                    handleId: row["handle_id"],
                    conversationId: conversationId
                )

                let senderAddress: String? = row["sender_address"]
                return (message, conversationId, senderAddress)
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

    // MARK: - Mark as Read

    /// Mark all unread messages in a conversation as read
    /// This writes to Apple's chat.db to sync read status with Messages.app
    public func markConversationAsRead(conversationId: String) async throws {
        let (messagesMarked, chatUpdated) = try await Task.detached { [dbPool] in
            try dbPool.write { db -> (Int, Bool) in
                let now = Int64(Date().timeIntervalSinceReferenceDate * 1_000_000_000)

                // 1. Mark individual messages as read
                try db.execute(sql: """
                    UPDATE message SET is_read = 1, date_read = ?
                    WHERE ROWID IN (
                        SELECT m.ROWID FROM message m
                        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                        JOIN chat c ON cmj.chat_id = c.ROWID
                        WHERE c.chat_identifier = ?
                        AND m.is_read = 0
                        AND m.is_from_me = 0
                    )
                    """, arguments: [now, conversationId])
                let messagesCount = db.changesCount

                // 2. Update the chat's last_read_message_timestamp to the latest message timestamp
                // This is what Messages.app uses to determine if the conversation has unread messages
                try db.execute(sql: """
                    UPDATE chat SET last_read_message_timestamp = (
                        SELECT MAX(m.date) FROM message m
                        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                        WHERE cmj.chat_id = chat.ROWID
                    )
                    WHERE chat_identifier = ?
                    """, arguments: [conversationId])
                let chatUpdated = db.changesCount > 0

                return (messagesCount, chatUpdated)
            }
        }.value
        // Open the conversation in Messages.app (in background) to trigger native read-marking
        // This is more reliable than database updates since Messages.app syncs via iCloud
        await openConversationInMessagesApp(conversationId: conversationId)

        serverLog("Marked \(messagesMarked) message(s) as read, chat updated: \(chatUpdated) for: \(conversationId)")
    }

    /// Opens a conversation in Messages.app without bringing it to the foreground
    /// This triggers Messages.app's internal read-marking mechanism
    private func openConversationInMessagesApp(conversationId: String) async {
        // Use messages:// URL scheme which works for both group chats and 1:1 conversations
        // Group chats: messages://open?chat=<chat_id>
        // 1:1 chats: messages://open?address=<phone_or_email>

        let url: String
        if conversationId.hasPrefix("chat") {
            // Group chat - use chat parameter
            url = "messages://open?chat=\(conversationId)"
        } else {
            // 1:1 chat - use address parameter (URL encode for special chars like +)
            let encoded = conversationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? conversationId
            url = "messages://open?address=\(encoded)"
        }

        // Use NSWorkspace to open the URL without activating Messages.app
        // The .withoutActivation option keeps the current app in the foreground
        guard let messagesURL = URL(string: url) else {
            serverLogWarning("Invalid URL for conversation: \(url)")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false  // Don't bring Messages to foreground

        do {
            try await NSWorkspace.shared.open(messagesURL, configuration: configuration)
            serverLogDebug("Opened conversation in Messages.app (background): \(conversationId)")
        } catch {
            serverLogWarning("Failed to open conversation in Messages.app: \(error)")
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

    // MARK: - Attachments

    /// Fetch all attachments for a specific message
    private nonisolated func fetchAttachmentsForMessage(db: Database, messageId: Int64) throws -> [Attachment] {
        let sql = """
            SELECT
                a.ROWID as id,
                a.guid,
                a.transfer_name as filename,
                a.mime_type,
                a.uti,
                a.total_bytes as size,
                a.is_outgoing,
                a.is_sticker,
                a.filename as file_path
            FROM attachment a
            JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
            WHERE maj.message_id = ?
            """

        let rows = try Row.fetchAll(db, sql: sql, arguments: [messageId])

        return rows.compactMap { row -> Attachment? in
            guard let id: Int64 = row["id"],
                  let guid: String = row["guid"] else {
                return nil
            }

            // Get the filename - prefer transfer_name, fallback to extracting from file_path
            let transferName: String? = row["filename"]
            let filePath: String? = row["file_path"]
            let filename = transferName ?? filePath?.components(separatedBy: "/").last ?? "attachment"

            // Generate thumbnail for images (if small enough)
            var thumbnailBase64: String? = nil
            let mimeType: String? = row["mime_type"]
            if let mimeType = mimeType, mimeType.hasPrefix("image/"), let filePath = filePath {
                thumbnailBase64 = generateThumbnail(forFilePath: filePath)
            }

            return Attachment(
                id: id,
                guid: guid,
                filename: filename,
                mimeType: mimeType,
                uti: row["uti"],
                size: row["size"] ?? 0,
                isOutgoing: (row["is_outgoing"] as Int?) == 1,
                isSticker: (row["is_sticker"] as Int?) == 1,
                thumbnailBase64: thumbnailBase64
            )
        }
    }

    /// Fetch a single attachment by ID (for serving files)
    public func fetchAttachment(id: Int64) throws -> (attachment: Attachment, filePath: String)? {
        try dbPool.read { db in
            let sql = """
                SELECT
                    a.ROWID as id,
                    a.guid,
                    a.transfer_name as filename,
                    a.mime_type,
                    a.uti,
                    a.total_bytes as size,
                    a.is_outgoing,
                    a.is_sticker,
                    a.filename as file_path
                FROM attachment a
                WHERE a.ROWID = ?
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [id]) else {
                return nil
            }

            guard let guid: String = row["guid"],
                  let filePath: String = row["file_path"] else {
                return nil
            }

            let transferName: String? = row["filename"]
            let filename = transferName ?? filePath.components(separatedBy: "/").last ?? "attachment"

            let attachment = Attachment(
                id: id,
                guid: guid,
                filename: filename,
                mimeType: row["mime_type"],
                uti: row["uti"],
                size: row["size"] ?? 0,
                isOutgoing: (row["is_outgoing"] as Int?) == 1,
                isSticker: (row["is_sticker"] as Int?) == 1,
                thumbnailBase64: nil  // Don't include thumbnail when serving file
            )

            // Expand ~ to home directory
            let expandedPath = filePath.replacingOccurrences(of: "~", with: NSHomeDirectory())

            return (attachment, expandedPath)
        }
    }

    /// Generate a thumbnail for an image file (max 300x300)
    private nonisolated func generateThumbnail(forFilePath path: String) -> String? {
        // Expand ~ to home directory
        let expandedPath = path.replacingOccurrences(of: "~", with: NSHomeDirectory())

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return nil
        }

        guard let image = NSImage(contentsOfFile: expandedPath) else {
            return nil
        }

        // Calculate thumbnail size (max 300x300, maintaining aspect ratio)
        let maxSize: CGFloat = 300
        let originalSize = image.size
        var thumbnailSize = originalSize

        if originalSize.width > maxSize || originalSize.height > maxSize {
            let widthRatio = maxSize / originalSize.width
            let heightRatio = maxSize / originalSize.height
            let ratio = min(widthRatio, heightRatio)
            thumbnailSize = CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
        }

        // Create thumbnail
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()

        // Convert to JPEG data
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }

        return jpegData.base64EncodedString()
    }

    // MARK: - Group Photos

    /// Look up group photo for a conversation by its guid
    /// Group photos are stored at ~/Library/Messages/Attachments/*/*/<guid>/GroupPhotoImage
    private nonisolated func lookupGroupPhoto(for guid: String) -> Data? {
        let fileManager = FileManager.default
        let attachmentsPath = NSHomeDirectory() + "/Library/Messages/Attachments"

        // The guid in the path may have special characters URL-encoded or replaced
        // Search for directories matching the pattern
        guard let level1 = try? fileManager.contentsOfDirectory(atPath: attachmentsPath) else {
            return nil
        }

        for dir1 in level1 {
            let level1Path = attachmentsPath + "/" + dir1
            guard let level2 = try? fileManager.contentsOfDirectory(atPath: level1Path) else {
                continue
            }

            for dir2 in level2 {
                let level2Path = level1Path + "/" + dir2

                // Check if this directory contains the guid
                if dir2.contains(guid) || dir2 == guid {
                    let photoPath = level2Path + "/GroupPhotoImage"
                    if fileManager.fileExists(atPath: photoPath) {
                        return try? Data(contentsOf: URL(fileURLWithPath: photoPath))
                    }
                }

                // Also check subdirectories (some photos are in at_0_<uuid>/<guid>/)
                guard let level3 = try? fileManager.contentsOfDirectory(atPath: level2Path) else {
                    continue
                }

                for dir3 in level3 {
                    if dir3.contains(guid) || dir3 == guid {
                        let photoPath = level2Path + "/" + dir3 + "/GroupPhotoImage"
                        if fileManager.fileExists(atPath: photoPath) {
                            return try? Data(contentsOf: URL(fileURLWithPath: photoPath))
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Private Helpers

    private nonisolated func conversationFromRow(_ row: Row, db: Database) throws -> Conversation {
        let chatId: Int64 = row["chat_id"]
        let chatIdentifier: String = row["chat_identifier"]

        let participants = try fetchHandlesForChat(db: db, chatId: chatId)
        let lastMessage = messageFromRow(row, conversationId: chatIdentifier)

        let chatStyle: Int? = row["chat_style"]
        let isGroup = chatStyle == 43
        let unreadCount: Int = row["unread_count"] ?? 0

        return Conversation(
            id: chatIdentifier,
            guid: row["chat_guid"],
            displayName: row["display_name"],
            participants: participants,
            lastMessage: lastMessage,
            isGroup: isGroup,
            unreadCount: unreadCount
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
