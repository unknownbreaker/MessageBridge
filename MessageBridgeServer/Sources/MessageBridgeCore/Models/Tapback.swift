import Foundation

/// Tapback reaction types matching Apple's chat.db associated_message_type values.
/// Add reactions use 2000-2005, remove reactions use 3000-3005.
public enum TapbackType: Int, Codable, Sendable, CaseIterable {
  case love = 2000
  case like = 2001
  case dislike = 2002
  case laugh = 2003
  case emphasis = 2004
  case question = 2005

  /// The emoji representation of this tapback type.
  public var emoji: String {
    switch self {
    case .love: return "❤️"
    case .like: return "👍"
    case .dislike: return "👎"
    case .laugh: return "😂"
    case .emphasis: return "‼️"
    case .question: return "❓"
    }
  }

  /// The associated_message_type value used when removing this tapback.
  /// Removal types are 1000 higher than addition types.
  public var removalType: Int {
    rawValue + 1000
  }

  /// Parse an associated_message_type value from chat.db.
  /// - Parameter associatedType: The associated_message_type value (2000-3005 range)
  /// - Returns: A tuple of (TapbackType, isRemoval) or nil if not a valid tapback type
  public static func from(associatedType: Int) -> (type: TapbackType, isRemoval: Bool)? {
    // Check if it's an add reaction (2000-2005)
    if let type = TapbackType(rawValue: associatedType) {
      return (type, false)
    }

    // Check if it's a remove reaction (3000-3005)
    let addType = associatedType - 1000
    if let type = TapbackType(rawValue: addType) {
      return (type, true)
    }

    return nil
  }
}

/// A tapback reaction on a message.
public struct Tapback: Codable, Sendable, Equatable {
  /// The type of tapback reaction.
  public let type: TapbackType

  /// The handle ID of the sender (e.g., "+15551234567" or "email@example.com").
  public let sender: String

  /// Whether this tapback was sent by the current user.
  public let isFromMe: Bool

  /// When the tapback was created.
  public let date: Date

  /// The GUID of the message this tapback is attached to.
  public let messageGUID: String

  public init(
    type: TapbackType,
    sender: String,
    isFromMe: Bool,
    date: Date,
    messageGUID: String
  ) {
    self.type = type
    self.sender = sender
    self.isFromMe = isFromMe
    self.date = date
    self.messageGUID = messageGUID
  }
}
