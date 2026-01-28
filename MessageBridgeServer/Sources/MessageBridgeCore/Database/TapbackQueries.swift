import Foundation
import GRDB

/// Queries for reading tapback reactions from Apple's chat.db.
///
/// Tapbacks are stored as messages with special `associated_message_type` values:
/// - 2000-2005: Add tapback (love, like, dislike, laugh, emphasis, question)
/// - 3000-3005: Remove tapback (cancels the corresponding add)
/// - `associated_message_guid` contains the GUID of the target message
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
  private func fetchTapbacks(db: Database, forGUIDs guids: [String]) throws -> [String: [Tapback]] {
    // Build placeholder string for IN clause
    let placeholders = guids.map { _ in "?" }.joined(separator: ", ")

    let sql = """
      SELECT
          m.ROWID,
          m.guid,
          m.associated_message_guid,
          m.associated_message_type,
          m.is_from_me,
          m.date,
          COALESCE(h.id, '') as sender
      FROM message m
      LEFT JOIN handle h ON m.handle_id = h.ROWID
      WHERE m.associated_message_guid IN (\(placeholders))
        AND m.associated_message_type BETWEEN 2000 AND 3005
      ORDER BY m.date ASC
      """

    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(guids))

    // Track active tapbacks per (targetGUID, sender, type)
    // Key: "targetGUID|sender|typeRawValue"
    // Value: Tapback or nil if removed
    var tapbackState: [String: Tapback?] = [:]

    for row in rows {
      guard
        let associatedGUID: String = row["associated_message_guid"],
        let associatedType: Int = row["associated_message_type"],
        let parsed = TapbackType.from(associatedType: associatedType)
      else {
        continue
      }

      let isFromMe: Int = row["is_from_me"] ?? 0
      let sender: String = row["sender"] ?? ""
      let dateValue: Int64 = row["date"] ?? 0

      // Build unique key for this sender+type+target combination
      let senderKey = isFromMe == 1 ? "__me__" : sender
      let stateKey = "\(associatedGUID)|\(senderKey)|\(parsed.type.rawValue)"

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
          messageGUID: associatedGUID
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
