import Foundation
import GRDB

/// Queries for reading tapback reactions from Apple's chat.db.
///
/// Tapbacks are stored as messages with special `associated_message_type` values:
/// - 2000-2005: Add classic tapback (love, like, dislike, laugh, emphasis, question)
/// - 2006: Add custom emoji tapback (iOS 17+), emoji in `associated_message_emoji`
/// - 3000-3006: Remove tapback (cancels the corresponding add)
/// - `associated_message_guid` contains the GUID of the target message (with `p:N/` or `bp:` prefix)
public struct TapbackQueries: Sendable {
  private let database: DatabaseReader

  public init(database: DatabaseReader) {
    self.database = database
  }

  /// Fetch tapbacks for a set of message GUIDs.
  /// Returns a dictionary mapping message GUID to its non-cancelled tapbacks.
  ///
  /// - Parameter guids: The GUIDs of messages to fetch tapbacks for
  /// - Returns: A dictionary where keys are message GUIDs and values are arrays of active tapbacks
  public func tapbacks(forMessageGUIDs guids: [String]) async throws -> [String: [Tapback]] {
    guard !guids.isEmpty else {
      return [:]
    }

    return try await database.read { db in
      try fetchTapbacks(db: db, forGUIDs: guids)
    }
  }

  /// Internal method to fetch and process tapbacks from the database.
  /// Strip the `p:N/` or `bp:` prefix from an associated_message_guid to get the raw message GUID.
  /// Apple stores tapback references as `p:0/MESSAGE_GUID` (part index prefix),
  /// `bp:MESSAGE_GUID` (balloon provider / link preview), or bare `MESSAGE_GUID`.
  private static let stripPrefixSQL = """
    CASE WHEN m.associated_message_guid LIKE 'p:%/%'
         THEN SUBSTR(m.associated_message_guid, INSTR(m.associated_message_guid, '/') + 1)
         WHEN m.associated_message_guid LIKE 'bp:%'
         THEN SUBSTR(m.associated_message_guid, 4)
         ELSE m.associated_message_guid
    END
    """

  private func fetchTapbacks(db: Database, forGUIDs guids: [String]) throws -> [String: [Tapback]] {
    // Build placeholder string for IN clause
    let placeholders = guids.map { _ in "?" }.joined(separator: ", ")

    let sql = """
      SELECT
          m.ROWID,
          m.guid,
          \(Self.stripPrefixSQL) as target_guid,
          m.associated_message_type,
          m.associated_message_emoji,
          m.is_from_me,
          m.date,
          COALESCE(h.id, '') as sender
      FROM message m
      LEFT JOIN handle h ON m.handle_id = h.ROWID
      WHERE (\(Self.stripPrefixSQL)) IN (\(placeholders))
        AND m.associated_message_type BETWEEN 2000 AND 3006
      ORDER BY m.date ASC
      """

    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(guids))

    // Track active tapbacks per (targetGUID, sender, type/emoji)
    // Key: "targetGUID|sender|typeRawValue|emoji" (emoji included for custom types)
    // Value: Tapback or nil if removed
    var tapbackState: [String: Tapback?] = [:]

    for row in rows {
      guard
        let targetGUID: String = row["target_guid"],
        let associatedType: Int = row["associated_message_type"],
        let parsed = TapbackType.from(associatedType: associatedType)
      else {
        continue
      }

      let isFromMe: Int = row["is_from_me"] ?? 0
      let sender: String = row["sender"] ?? ""
      let dateValue: Int64 = row["date"] ?? 0
      let customEmoji: String? = row["associated_message_emoji"]

      // Build unique key — for custom emoji, include the emoji to allow multiple different reactions
      let senderKey = isFromMe == 1 ? "__me__" : sender
      let emojiKey = customEmoji ?? ""
      let stateKey = "\(targetGUID)|\(senderKey)|\(parsed.type.rawValue)|\(emojiKey)"

      if parsed.isRemoval {
        // Mark as removed (nil)
        tapbackState[stateKey] = nil
      } else {
        // Add or update the tapback
        let date = Message.dateFromAppleTimestamp(dateValue)
        let tapback = Tapback(
          type: parsed.type,
          sender: sender,
          isFromMe: isFromMe == 1,
          date: date,
          messageGUID: targetGUID,
          emoji: customEmoji
        )
        tapbackState[stateKey] = tapback
      }
    }

    // Group active tapbacks by target message GUID
    var result: [String: [Tapback]] = [:]

    for (_, tapback) in tapbackState {
      guard let tapback = tapback else {
        // This tapback was removed
        continue
      }

      result[tapback.messageGUID, default: []].append(tapback)
    }

    // Sort tapbacks within each message by date
    for guid in result.keys {
      result[guid]?.sort { $0.date < $1.date }
    }

    return result
  }
}
