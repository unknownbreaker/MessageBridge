import AppKit
import Foundation
import GRDB

/// Result of attempting to sync read state with Messages.app
public enum SyncResult: Sendable, Equatable {
  case success
  case failed(reason: String)
}

/// Information about a group chat for UI search operations
public struct GroupChatInfo: Sendable {
  public let conversationId: String
  public let displayName: String?
  public let handles: [String]

  public init(conversationId: String, displayName: String?, handles: [String]) {
    self.conversationId = conversationId
    self.displayName = displayName
    self.handles = handles
  }
}

/// Provides read-only access to the macOS Messages database (chat.db)
public actor ChatDatabase: ChatDatabaseProtocol {
  private nonisolated let dbPool: DatabasePool
  private let contactManager: ContactManager
  private var lastImagentRestart: Date = .distantPast

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

  public func fetchRecentConversations(limit: Int = 50, offset: Int = 0) async throws
    -> [Conversation]
  {
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

  private nonisolated func fetchRecentConversationsFromDB(limit: Int, offset: Int) throws
    -> [Conversation]
  {
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

  public func fetchMessages(conversationId: String, limit: Int = 50, offset: Int = 0) async throws
    -> [Message]
  {
    // First fetch messages from the database (synchronously)
    let messages = try fetchMessagesFromDB(
      conversationId: conversationId, limit: limit, offset: offset)

    // Then fetch tapbacks for all messages (asynchronously)
    let messageGUIDs = messages.map { $0.guid }
    let tapbackQueries = TapbackQueries(database: dbPool)
    let tapbacksByGUID = try await tapbackQueries.tapbacks(forMessageGUIDs: messageGUIDs)

    // Attach tapbacks to messages
    let messagesWithTapbacks = messages.map { message in
      var updated = message
      updated.tapbacks = tapbacksByGUID[message.guid] ?? []
      return updated
    }

    return messagesWithTapbacks
  }

  private nonisolated func fetchMessagesFromDB(conversationId: String, limit: Int, offset: Int)
    throws
    -> [Message]
  {
    return try dbPool.read { db in
      let sql = """
        SELECT
            m.ROWID as id,
            m.guid,
            m.text,
            m.attributedBody,
            m.date,
            m.is_from_me,
            m.handle_id,
            m.balloon_bundle_id,
            m.payload_data
        FROM message m
        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE c.chat_identifier = ?
          AND (m.associated_message_type IS NULL OR m.associated_message_type = 0)
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

        let dateDeliveredRaw: Int64? = row["date_delivered"]
        let dateReadRaw: Int64? = row["date_read"]

        // Extract link preview from payload_data if this is a URL balloon
        var linkPreview: LinkPreview? = nil
        let balloonBundleId: String? = row["balloon_bundle_id"]
        if balloonBundleId == "com.apple.messages.URLBalloonProvider",
          let payloadData: Data = row["payload_data"]
        {
          linkPreview = LinkPreviewExtractor.extract(from: payloadData)
        }

        // Get preview image from plugin payload attachments
        if linkPreview != nil {
          let previewImageBase64 = self.fetchLinkPreviewImage(db: db, messageId: messageId)
          if let imageBase64 = previewImageBase64 {
            linkPreview = LinkPreview(
              url: linkPreview!.url,
              title: linkPreview!.title,
              summary: linkPreview!.summary,
              siteName: linkPreview!.siteName,
              imageBase64: imageBase64
            )
          }
        }

        return Message(
          id: messageId,
          guid: row["guid"],
          text: messageText,
          date: Message.dateFromAppleTimestamp(row["date"]),
          isFromMe: (row["is_from_me"] as Int?) == 1,
          handleId: row["handle_id"],
          conversationId: conversationId,
          attachments: attachments,
          linkPreview: linkPreview
        )
      }
    }
  }

  // MARK: - New Message Detection (Fast Path)

  /// Fetch messages newer than a given ID - optimized for real-time detection
  /// This is a fast query that skips contact lookups and photo generation
  public nonisolated func fetchMessagesNewerThan(id: Int64, limit: Int = 20) throws -> [(
    message: Message, conversationId: String, senderAddress: String?
  )] {
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
          AND (m.associated_message_type IS NULL OR m.associated_message_type = 0)
        ORDER BY m.ROWID ASC
        LIMIT ?
        """

      let rows = try Row.fetchAll(db, sql: sql, arguments: [id, limit])

      return rows.compactMap { row -> (Message, String, String?)? in
        guard let messageId: Int64 = row["id"],
          let guid: String = row["guid"],
          let conversationId: String = row["chat_identifier"]
        else {
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

        let dateDeliveredRaw: Int64? = row["date_delivered"]
        let dateReadRaw: Int64? = row["date_read"]

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

  // MARK: - Tapback Detection (Fast Path)

  /// Fetch tapback rows newer than a given ROWID - optimized for real-time detection
  /// This queries for messages with associated_message_type between 2000-3006 (tapbacks)
  public nonisolated func fetchTapbacksNewerThan(id: Int64, limit: Int = 20) throws -> [(
    rowId: Int64, tapback: Tapback, conversationId: String, isRemoval: Bool
  )] {
    try dbPool.read { db in
      // Query for tapback messages (associated_message_type 2000-3006)
      // Join to get the target message's conversation
      // Strip the p:N/ or bp: prefix from associated_message_guid to get the raw target GUID.
      // Apple stores tapback references as "p:0/MESSAGE_GUID" (part index),
      // "bp:MESSAGE_GUID" (balloon provider / link preview), or bare "MESSAGE_GUID".
      let stripPrefix = """
        CASE WHEN m.associated_message_guid LIKE 'p:%/%'
             THEN SUBSTR(m.associated_message_guid, INSTR(m.associated_message_guid, '/') + 1)
             WHEN m.associated_message_guid LIKE 'bp:%'
             THEN SUBSTR(m.associated_message_guid, 4)
             ELSE m.associated_message_guid
        END
        """

      let sql = """
        SELECT
            m.ROWID as id,
            m.guid,
            (\(stripPrefix)) as target_guid,
            m.associated_message_type,
            m.associated_message_emoji,
            m.is_from_me,
            m.date,
            COALESCE(h.id, '') as sender,
            c.chat_identifier as conversation_id
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        JOIN message target_msg ON target_msg.guid = (\(stripPrefix))
        JOIN chat_message_join cmj ON target_msg.ROWID = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE m.ROWID > ?
          AND m.associated_message_type BETWEEN 2000 AND 3006
        ORDER BY m.ROWID ASC
        LIMIT ?
        """

      let rows = try Row.fetchAll(db, sql: sql, arguments: [id, limit])

      return rows.compactMap { row -> (Int64, Tapback, String, Bool)? in
        guard
          let rowId: Int64 = row["id"],
          let targetGUID: String = row["target_guid"],
          let associatedType: Int = row["associated_message_type"],
          let conversationId: String = row["conversation_id"],
          let parsed = TapbackType.from(associatedType: associatedType)
        else {
          return nil
        }

        let isFromMe: Int = row["is_from_me"] ?? 0
        let sender: String = row["sender"] ?? ""
        let dateValue: Int64 = row["date"] ?? 0
        let customEmoji: String? = row["associated_message_emoji"]

        let tapback = Tapback(
          type: parsed.type,
          sender: sender,
          isFromMe: isFromMe == 1,
          date: Message.dateFromAppleTimestamp(dateValue),
          messageGUID: targetGUID,
          emoji: customEmoji
        )

        return (rowId, tapback, conversationId, parsed.isRemoval)
      }
    }
  }

  // MARK: - Search

  public func searchMessages(query: String, limit: Int = 50) async throws -> [Message] {
    // First fetch messages from the database (synchronously)
    let messages = try searchMessagesFromDB(query: query, limit: limit)

    // Then fetch tapbacks for all messages (asynchronously)
    let messageGUIDs = messages.map { $0.guid }
    let tapbackQueries = TapbackQueries(database: dbPool)
    let tapbacksByGUID = try await tapbackQueries.tapbacks(forMessageGUIDs: messageGUIDs)

    // Attach tapbacks to messages
    let messagesWithTapbacks = messages.map { message in
      var updated = message
      updated.tapbacks = tapbacksByGUID[message.guid] ?? []
      return updated
    }

    return messagesWithTapbacks
  }

  private nonisolated func searchMessagesFromDB(query: String, limit: Int) throws -> [Message] {
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
          AND (m.associated_message_type IS NULL OR m.associated_message_type = 0)
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
  /// - Returns: SyncResult indicating if Messages.app sync was successful
  public func markConversationAsRead(conversationId: String) async throws -> SyncResult {
    let (messagesMarked, chatUpdated) = try await Task.detached { [dbPool] in
      try dbPool.write { db -> (Int, Bool) in
        let now = Int64(Date().timeIntervalSinceReferenceDate * 1_000_000_000)

        // 1. Mark individual messages as read
        try db.execute(
          sql: """
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
        try db.execute(
          sql: """
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
    let syncResult = await syncReadStateWithMessagesApp(conversationId: conversationId)

    serverLog(
      "Marked \(messagesMarked) message(s) as read, chat updated: \(chatUpdated) for: \(conversationId)"
    )

    return syncResult
  }

  /// Nudges Messages.app to pick up the read-state changes written to chat.db.
  ///
  /// For 1:1 chats the messages:// URL scheme reliably navigates Messages.app to the
  /// conversation (without activating the window), which triggers its internal read-marking.
  ///
  /// For group chats, we use UI search automation to open the specific chat. If the chat
  /// has duplicate participants with another chat, we use the display name search which
  /// requires Accessibility permissions.
  ///
  /// - Returns: SyncResult indicating if the sync was successful
  private func syncReadStateWithMessagesApp(conversationId: String) async -> SyncResult {
    let isGroupChat = conversationId.lowercased().hasPrefix("chat")
    serverLog("syncReadStateWithMessagesApp: \(conversationId), isGroupChat: \(isGroupChat)")

    if isGroupChat {
      return await openGroupChatViaSearch(conversationId: conversationId)
    } else {
      await openConversationViaURLScheme(conversationId: conversationId)
      return .success
    }
  }

  /// Opens a group chat by searching for it, using the appropriate strategy based on
  /// whether there are duplicate chats with the same participants.
  /// - Returns: SyncResult indicating if the operation was successful
  private func openGroupChatViaSearch(conversationId: String) async -> SyncResult {
    // Get participant handles and chat info for this group chat
    guard let chatInfo = getGroupChatInfo(conversationId: conversationId),
      !chatInfo.handles.isEmpty
    else {
      serverLogWarning("Could not get info for group chat: \(conversationId)")
      return .failed(reason: "Could not get chat info")
    }

    // Check if there are other chats with the exact same participants
    let hasDuplicates = hasChatsWithSameParticipants(
      conversationId: conversationId, handles: chatInfo.handles)

    if hasDuplicates {
      // Fall back to UI search by chat name (requires Accessibility)
      serverLog("openGroupChatViaSearch: duplicate participants detected, using UI search")
      return await openGroupChatViaUISearch(chatInfo: chatInfo)
    } else {
      // Use URL scheme with addresses (no special permissions needed)
      let addressList = chatInfo.handles.joined(separator: ",")
      guard let url = URL(string: "messages://open?addresses=\(addressList)") else {
        serverLogWarning("Could not build URL for group chat: \(conversationId)")
        return .failed(reason: "Could not build URL")
      }

      serverLog("openGroupChatViaSearch: opening URL = \(url)")
      _ = await MainActor.run {
        NSWorkspace.shared.open(url)
      }
      return .success
    }
  }

  /// Gets display name and handles for a group chat
  private nonisolated func getGroupChatInfo(conversationId: String) -> GroupChatInfo? {
    do {
      return try dbPool.read { [self] db -> GroupChatInfo? in
        // Get the chat's ROWID and display_name
        let chatRow = try Row.fetchOne(
          db,
          sql: """
            SELECT ROWID, display_name
            FROM chat
            WHERE chat_identifier = ?
            """,
          arguments: [conversationId]
        )

        guard let chatRow = chatRow,
          let chatId: Int64 = chatRow["ROWID"]
        else {
          return nil
        }

        let displayName: String? = chatRow["display_name"]

        // Get the handles for this chat
        let handles = try self.fetchHandlesForChat(db: db, chatId: chatId)
        let handleAddresses = handles.map { $0.address }

        return GroupChatInfo(
          conversationId: conversationId,
          displayName: displayName,
          handles: handleAddresses
        )
      }
    } catch {
      serverLogWarning("Failed to get group chat info: \(error)")
      return nil
    }
  }

  /// Checks if there are other chats with the exact same set of participants
  private nonisolated func hasChatsWithSameParticipants(conversationId: String, handles: [String])
    -> Bool
  {
    guard !handles.isEmpty else { return false }

    do {
      return try dbPool.read { [self] db -> Bool in
        // Find all chats that have ALL of the same handles (same participant count, all matching)
        // This is done by:
        // 1. Finding chats with the exact same number of participants
        // 2. Checking that all handles are shared

        let sortedHandles = handles.sorted()
        let handleCount = handles.count

        // Get all group chats with the same participant count
        let candidateChats = try Row.fetchAll(
          db,
          sql: """
            SELECT c.ROWID, c.chat_identifier, COUNT(chj.handle_id) as handle_count
            FROM chat c
            JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
            WHERE c.chat_identifier != ?
            AND c.chat_identifier LIKE 'chat%'
            GROUP BY c.ROWID
            HAVING handle_count = ?
            """,
          arguments: [conversationId, handleCount]
        )

        for candidateRow in candidateChats {
          guard let candidateChatId: Int64 = candidateRow["ROWID"] else { continue }

          // Get the handles for this candidate chat
          let candidateHandles = try self.fetchHandlesForChat(db: db, chatId: candidateChatId)
          let candidateAddresses = candidateHandles.map { $0.address }.sorted()

          // If all addresses match, we have a duplicate
          if candidateAddresses == sortedHandles {
            return true
          }
        }

        return false
      }
    } catch {
      serverLogWarning("Failed to check for duplicate chats: \(error)")
      return false
    }
  }

  /// Opens a 1:1 conversation via the messages:// URL scheme without activating Messages.app.
  private func openConversationViaURLScheme(conversationId: String) async {
    let encoded =
      conversationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      ?? conversationId
    let urlString = "messages://open?address=\(encoded)"

    guard let messagesURL = URL(string: urlString) else {
      serverLogWarning("Invalid URL for conversation: \(urlString)")
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false

    do {
      try await NSWorkspace.shared.open(messagesURL, configuration: configuration)
      serverLogDebug("Opened conversation in Messages.app: \(conversationId)")
    } catch {
      serverLogWarning("Failed to open conversation in Messages.app: \(error)")
    }
  }

  /// Restarts the imagent daemon so Messages.app re-reads chat.db read state.
  /// imagent is automatically relaunched by launchd within seconds.
  /// Debounced to at most once every 5 seconds to avoid thrashing when marking
  /// multiple conversations as read in quick succession.
  private func restartImagent() async {
    let now = Date()
    guard now.timeIntervalSince(lastImagentRestart) > 5 else {
      serverLogDebug("Skipping imagent restart (debounced)")
      return
    }
    lastImagentRestart = now

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .utility).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["imagent"]

        do {
          try process.run()
          process.waitUntilExit()
          serverLogDebug("Restarted imagent to sync read state")
        } catch {
          serverLogWarning("Failed to restart imagent: \(error)")
        }

        continuation.resume()
      }
    }
  }

  // MARK: - AppleScript Builders

  /// Builds the AppleScript for searching Messages.app by directly targeting the search field.
  /// SAFETY: This script finds the search field via accessibility role (AXSearchField) and clicks it
  /// to focus, rather than relying on Cmd+F which can fail and cause keystrokes to go into the
  /// message compose field — accidentally sending the search term as a message.
  /// - Parameter searchString: The chat name to search for
  /// - Returns: AppleScript source code
  public static func buildSearchScript(searchString: String) -> String {
    let escapedSearch =
      searchString
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")

    return """
      tell application "Messages" to activate
      delay 0.3

      tell application "System Events"
          tell process "Messages"
              -- Find the search field by accessibility role (AXSearchField).
              -- This is safer than Cmd+F which may fail to focus the search field,
              -- causing keystrokes to go into the message compose field.
              set searchField to missing value
              try
                  set allElements to entire contents of front window
                  repeat with elem in allElements
                      try
                          if class of elem is text field and subrole of elem is "AXSearchField" then
                              set searchField to elem
                              exit repeat
                          end if
                      end try
                  end repeat
              end try

              if searchField is missing value then
                  return "no_search_field"
              end if

              -- Click the search field to ensure it has focus
              click searchField
              delay 0.2

              -- Clear any existing text
              keystroke "a" using command down
              delay 0.05
              key code 51 -- Backspace
              delay 0.1

              -- Type the search string
              keystroke "\(escapedSearch)"
              delay 0.3

              -- Verify text was entered in the SEARCH field, not the compose field.
              -- If verification fails, abort without pressing Return to avoid sending a message.
              set textConfirmed to false
              repeat 10 times
                  try
                      set fieldVal to value of searchField
                      if fieldVal contains "\(escapedSearch)" then
                          set textConfirmed to true
                          exit repeat
                      end if
                  end try
                  delay 0.15
              end repeat

              if not textConfirmed then
                  -- Text didn't reach the search field. Press Escape and abort.
                  key code 53
                  return "wrong_field"
              end if

              -- Wait for search results to populate, then check once
              delay 1.0
              set resultsFound to false
              try
                  set allElements to entire contents of front window
                  repeat with elem in allElements
                      try
                          if class of elem is static text and value of elem is "Conversations" then
                              set resultsFound to true
                              exit repeat
                          end if
                      end try
                  end repeat
              end try

              if resultsFound then
                  -- Select first result
                  key code 125
                  delay 0.1
                  key code 36
                  delay 0.2
                  key code 53
                  return "success"
              else
                  key code 53
                  return "no_results"
              end if
          end tell
      end tell
      """
  }

  /// Executes the search AppleScript and returns the result
  /// - Parameter searchString: The chat name to search for
  /// - Returns: "success" if search worked, "no_results" if timed out, "error" if script failed
  private func executeSearchScript(searchString: String) async -> String {
    let script = ChatDatabase.buildSearchScript(searchString: searchString)

    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error = error {
          let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
          serverLogWarning("Search script error: \(errorMessage)")
          continuation.resume(returning: "error")
        } else if let resultString = result?.stringValue {
          continuation.resume(returning: resultString)
        } else {
          continuation.resume(returning: "error")
        }
      }
    }
  }

  /// Clears the search field by pressing Escape
  private func clearSearchField() async {
    let script = """
      tell application "System Events"
          tell process "Messages"
              key code 53
              delay 0.2
          end tell
      end tell
      """

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&error)
        continuation.resume()
      }
    }
  }

  /// Opens a group chat using UI search with retry and fallback (requires Accessibility permission)
  /// - Returns: SyncResult indicating success or failure with reason
  private func openGroupChatViaUISearch(chatInfo: GroupChatInfo) async -> SyncResult {
    guard let searchString = chatInfo.displayName, !searchString.isEmpty else {
      serverLogWarning("Cannot use UI search: no display name for chat \(chatInfo.conversationId)")
      // Fall back to addresses even though duplicates exist - better than nothing
      return await fallbackToURLScheme(chatInfo: chatInfo)
    }

    serverLog("openGroupChatViaUISearch: searching for '\(searchString)'")

    // Attempt 1
    let result1 = await executeSearchScript(searchString: searchString)
    if result1 == "success" {
      serverLog("openGroupChatViaUISearch: success on first attempt")
      return .success
    }

    // If the search field wasn't found, no point retrying — go straight to fallback
    if result1 == "no_search_field" {
      serverLog("openGroupChatViaUISearch: search field not found, falling back to URL scheme")
      return await fallbackToURLScheme(chatInfo: chatInfo)
    }

    serverLog("openGroupChatViaUISearch: first attempt returned '\(result1)', retrying...")

    // Clear and retry once
    await clearSearchField()
    try? await Task.sleep(for: .milliseconds(300))

    let result2 = await executeSearchScript(searchString: searchString)
    if result2 == "success" {
      serverLog("openGroupChatViaUISearch: success on retry")
      return .success
    }

    serverLog("openGroupChatViaUISearch: retry returned '\(result2)', falling back to URL scheme")

    // Fallback to URL scheme
    return await fallbackToURLScheme(chatInfo: chatInfo)
  }

  /// Falls back to opening via URL scheme when UI search fails
  private func fallbackToURLScheme(chatInfo: GroupChatInfo) async -> SyncResult {
    let addressList = chatInfo.handles.joined(separator: ",")
    guard let url = URL(string: "messages://open?addresses=\(addressList)") else {
      return .failed(reason: "Could not build fallback URL")
    }

    serverLog("openGroupChatViaUISearch: opening fallback URL = \(url)")

    _ = await MainActor.run {
      NSWorkspace.shared.open(url)
    }

    return .failed(reason: "Read status could not be synced to Messages.app")
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
  private nonisolated func fetchAttachmentsForMessage(db: Database, messageId: Int64) throws
    -> [Attachment]
  {
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
        let guid: String = row["guid"]
      else {
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
    }.filter { !$0.shouldFilter }
  }

  /// Fetch a single attachment by ID (for serving files)
  public func fetchAttachment(id: Int64) async throws -> (attachment: Attachment, filePath: String)?
  {
    try fetchAttachmentFromDB(id: id)
  }

  private nonisolated func fetchAttachmentFromDB(id: Int64) throws -> (
    attachment: Attachment, filePath: String
  )? {
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
        let filePath: String = row["file_path"]
      else {
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

  /// Fetch the preview image for a link preview message.
  ///
  /// Messages.app stores link preview images as `pluginPayloadAttachment` files
  /// with **no MIME type or UTI** (they use a dynamic UTI). Each message typically
  /// has multiple attachments: a small favicon/icon and the larger og:image preview.
  /// We pick the largest file (by total_bytes) since that's the actual preview image.
  private nonisolated func fetchLinkPreviewImage(db: Database, messageId: Int64) -> String? {
    // Get all pluginPayloadAttachment files for this message, ordered by size descending.
    // The largest is typically the og:image preview; smaller ones are favicons/icons.
    // We don't filter by mime_type/uti because Messages.app leaves them empty.
    let sql = """
      SELECT a.filename as file_path, a.total_bytes as size
      FROM attachment a
      JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
      WHERE maj.message_id = ?
        AND a.transfer_name LIKE '%pluginPayloadAttachment%'
        AND a.total_bytes > 0
      ORDER BY a.total_bytes DESC
      """

    guard let rows = try? Row.fetchAll(db, sql: sql, arguments: [messageId]) else {
      return nil
    }

    // Try each attachment starting from the largest — generate thumbnail from the
    // first one that is actually a valid image file on disk
    for row in rows {
      guard let filePath: String = row["file_path"] else { continue }
      if let thumbnail = generateThumbnail(forFilePath: filePath) {
        return thumbnail
      }
    }

    return nil
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
    image.draw(
      in: NSRect(origin: .zero, size: thumbnailSize),
      from: NSRect(origin: .zero, size: originalSize),
      operation: .copy,
      fraction: 1.0)
    thumbnail.unlockFocus()

    // Convert to JPEG data
    guard let tiffData = thumbnail.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    else {
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
      let messageDate: Int64 = row["message_date"]
    else {
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
