import Foundation

// MARK: - Handle

public struct Handle: Codable, Identifiable, Hashable, Sendable {
  public let id: Int64
  public let address: String
  public let service: String
  public let contactName: String?
  public let photoBase64: String?  // Contact photo as base64-encoded data

  public init(
    id: Int64, address: String, service: String, contactName: String? = nil,
    photoBase64: String? = nil
  ) {
    self.id = id
    self.address = address
    self.service = service
    self.contactName = contactName
    self.photoBase64 = photoBase64
  }

  /// Display name - prefers contact name, falls back to address
  public var displayName: String {
    contactName ?? address
  }

  public var displayAddress: String {
    address
  }

  /// Decoded photo data from base64
  public var photoData: Data? {
    guard let photoBase64 = photoBase64 else { return nil }
    return Data(base64Encoded: photoBase64)
  }
}

// MARK: - TapbackType

/// The type of tapback reaction (matching iMessage tapback types)
public enum TapbackType: Int, Codable, Sendable, CaseIterable {
  case love = 2000
  case like = 2001
  case dislike = 2002
  case laugh = 2003
  case emphasis = 2004
  case question = 2005
  case customEmoji = 2006

  /// The default emoji for classic tapback types.
  /// For `.customEmoji`, use the `emoji` field on the `Tapback` struct instead.
  public var emoji: String {
    switch self {
    case .love: return "❤️"
    case .like: return "👍"
    case .dislike: return "👎"
    case .laugh: return "😂"
    case .emphasis: return "‼️"
    case .question: return "❓"
    case .customEmoji: return "😀"
    }
  }
}

// MARK: - Tapback

/// Represents a tapback reaction on a message
public struct Tapback: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String { "\(messageGUID)-\(sender)-\(type.rawValue)-\(emoji ?? "")" }
  public let type: TapbackType
  public let sender: String
  public let isFromMe: Bool
  public let date: Date
  public let messageGUID: String
  /// The custom emoji for `.customEmoji` type tapbacks (iOS 17+).
  /// Nil for classic tapback types.
  public let emoji: String?

  public init(
    type: TapbackType, sender: String, isFromMe: Bool, date: Date, messageGUID: String,
    emoji: String? = nil
  ) {
    self.type = type
    self.sender = sender
    self.isFromMe = isFromMe
    self.date = date
    self.messageGUID = messageGUID
    self.emoji = emoji
  }

  /// The emoji to display for this tapback.
  /// Uses the custom emoji for `.customEmoji` type, otherwise the classic type's emoji.
  public var displayEmoji: String {
    if type == .customEmoji, let emoji = emoji {
      return emoji
    }
    return type.emoji
  }
}

// MARK: - Attachment

/// Represents a file attachment (image, video, audio, document) in a message
public struct Attachment: Codable, Identifiable, Hashable, Sendable {
  public let id: Int64  // ROWID from database
  public let guid: String  // Unique identifier
  public let filename: String  // Original filename
  public let mimeType: String?  // MIME type (image/jpeg, video/mp4, etc.)
  public let uti: String?  // Uniform Type Identifier
  public let size: Int64  // File size in bytes
  public let isOutgoing: Bool  // Whether we sent this attachment
  public let isSticker: Bool  // Whether this is a sticker
  public let thumbnailBase64: String?  // Thumbnail image as base64 (for images/videos)

  public init(
    id: Int64,
    guid: String,
    filename: String,
    mimeType: String? = nil,
    uti: String? = nil,
    size: Int64,
    isOutgoing: Bool,
    isSticker: Bool,
    thumbnailBase64: String? = nil
  ) {
    self.id = id
    self.guid = guid
    self.filename = filename
    self.mimeType = mimeType
    self.uti = uti
    self.size = size
    self.isOutgoing = isOutgoing
    self.isSticker = isSticker
    self.thumbnailBase64 = thumbnailBase64
  }

  // MARK: - Attachment Type Detection

  /// The type category of this attachment
  public var attachmentType: AttachmentType {
    if let mimeType = mimeType {
      if mimeType.hasPrefix("image/") {
        return .image
      } else if mimeType.hasPrefix("video/") {
        return .video
      } else if mimeType.hasPrefix("audio/") {
        return .audio
      }
    }

    // Fallback to UTI-based detection
    if let uti = uti {
      if uti.contains("image") {
        return .image
      } else if uti.contains("movie") || uti.contains("video") {
        return .video
      } else if uti.contains("audio") {
        return .audio
      }
    }

    return .document
  }

  public var isImage: Bool { attachmentType == .image }
  public var isVideo: Bool { attachmentType == .video }
  public var isAudio: Bool { attachmentType == .audio }
  public var isDocument: Bool { attachmentType == .document }

  /// Human-readable file size (e.g., "1.2 MB")
  public var formattedSize: String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  /// Decoded thumbnail data from base64
  public var thumbnailData: Data? {
    guard let thumbnailBase64 = thumbnailBase64 else { return nil }
    return Data(base64Encoded: thumbnailBase64)
  }
}

/// Categories of attachment types
public enum AttachmentType: String, Codable, Sendable {
  case image
  case video
  case audio
  case document
}

// MARK: - LinkPreview

/// Rich link preview metadata from server (extracted from iMessage payload_data)
public struct LinkPreview: Codable, Hashable, Sendable {
  public let url: String
  public let title: String?
  public let summary: String?
  public let siteName: String?
  public let imageBase64: String?

  public init(
    url: String,
    title: String? = nil,
    summary: String? = nil,
    siteName: String? = nil,
    imageBase64: String? = nil
  ) {
    self.url = url
    self.title = title
    self.summary = summary
    self.siteName = siteName
    self.imageBase64 = imageBase64
  }

  /// Extract domain from URL for display (e.g., "apple.com" from "https://www.apple.com/...")
  public var domain: String {
    guard let urlObj = URL(string: url), let host = urlObj.host() else {
      return url
    }
    if host.hasPrefix("www.") {
      return String(host.dropFirst(4))
    }
    return host
  }

  /// Decoded image data from base64
  public var imageData: Data? {
    guard let imageBase64 = imageBase64 else { return nil }
    return Data(base64Encoded: imageBase64)
  }
}

// MARK: - DeliveryStatus

/// Delivery status of a sent message
public enum DeliveryStatus: String, Codable, Sendable {
  case none  // Received messages (no status shown)
  case sent  // Sent, no delivery confirmation yet
  case delivered  // Delivered to recipient's device
  case read  // Recipient opened conversation
}

// MARK: - Message

public struct Message: Codable, Identifiable, Hashable, Sendable {
  public let id: Int64
  public let guid: String
  public let text: String?
  public let date: Date
  public let isFromMe: Bool
  public let handleId: Int64?
  public let conversationId: String
  public let attachments: [Attachment]
  public let detectedCodes: [DetectedCode]?
  public let highlights: [TextHighlight]?
  public let mentions: [Mention]?
  public var tapbacks: [Tapback]?
  public let dateDelivered: Date?
  public let dateRead: Date?
  public let linkPreview: LinkPreview?

  enum CodingKeys: String, CodingKey {
    case id, guid, text, date, isFromMe, handleId, conversationId, attachments
    case detectedCodes, highlights, mentions, tapbacks
    case dateDelivered, dateRead, linkPreview
  }

  public init(
    id: Int64, guid: String, text: String?, date: Date, isFromMe: Bool, handleId: Int64?,
    conversationId: String, attachments: [Attachment] = [],
    detectedCodes: [DetectedCode]? = nil,
    highlights: [TextHighlight]? = nil,
    mentions: [Mention]? = nil,
    tapbacks: [Tapback]? = nil,
    dateDelivered: Date? = nil,
    dateRead: Date? = nil,
    linkPreview: LinkPreview? = nil
  ) {
    self.id = id
    self.guid = guid
    self.text = text
    self.date = date
    self.isFromMe = isFromMe
    self.handleId = handleId
    self.conversationId = conversationId
    self.attachments = attachments
    self.detectedCodes = detectedCodes
    self.highlights = highlights
    self.mentions = mentions
    self.tapbacks = tapbacks
    self.dateDelivered = dateDelivered
    self.dateRead = dateRead
    self.linkPreview = linkPreview
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int64.self, forKey: .id)
    guid = try container.decode(String.self, forKey: .guid)
    text = try container.decodeIfPresent(String.self, forKey: .text)
    date = try container.decode(Date.self, forKey: .date)
    isFromMe = try container.decode(Bool.self, forKey: .isFromMe)
    handleId = try container.decodeIfPresent(Int64.self, forKey: .handleId)
    conversationId = try container.decode(String.self, forKey: .conversationId)
    attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    detectedCodes = try container.decodeIfPresent([DetectedCode].self, forKey: .detectedCodes)
    highlights = try container.decodeIfPresent([TextHighlight].self, forKey: .highlights)
    mentions = try container.decodeIfPresent([Mention].self, forKey: .mentions)
    tapbacks = try container.decodeIfPresent([Tapback].self, forKey: .tapbacks)
    dateDelivered = try container.decodeIfPresent(Date.self, forKey: .dateDelivered)
    dateRead = try container.decodeIfPresent(Date.self, forKey: .dateRead)
    linkPreview = try container.decodeIfPresent(LinkPreview.self, forKey: .linkPreview)
  }

  public var hasText: Bool {
    guard let text = text else { return false }
    return !text.isEmpty
  }

  /// Whether this message has any attachments
  public var hasAttachments: Bool {
    !attachments.isEmpty
  }

  public var deliveryStatus: DeliveryStatus {
    if dateRead != nil { return .read }
    if dateDelivered != nil { return .delivered }
    if isFromMe { return .sent }
    return .none
  }
}

// MARK: - Conversation

public struct Conversation: Codable, Identifiable, Sendable {
  public let id: String
  public let guid: String
  private let _displayName: String?
  public let participants: [Handle]
  public let lastMessage: Message?
  public let isGroup: Bool
  public let groupPhotoBase64: String?  // Group photo as base64-encoded image (PNG)
  public let unreadCount: Int  // Number of unread messages
  public let pinnedIndex: Int?  // Messages.app pin position (0-8), nil if unpinned

  enum CodingKeys: String, CodingKey {
    case id, guid, participants, lastMessage, isGroup, groupPhotoBase64, unreadCount, pinnedIndex
    case _displayName = "displayName"
  }

  public init(
    id: String, guid: String, displayName: String?, participants: [Handle], lastMessage: Message?,
    isGroup: Bool, groupPhotoBase64: String? = nil, unreadCount: Int = 0, pinnedIndex: Int? = nil
  ) {
    self.id = id
    self.guid = guid
    self._displayName = displayName
    self.participants = participants
    self.lastMessage = lastMessage
    self.isGroup = isGroup
    self.groupPhotoBase64 = groupPhotoBase64
    self.unreadCount = unreadCount
    self.pinnedIndex = pinnedIndex
  }

  /// Whether this conversation has unread messages
  public var hasUnread: Bool {
    unreadCount > 0
  }

  /// Raw display name value (nil if not set, used when recreating conversation)
  public var rawDisplayName: String? {
    _displayName
  }

  public var displayName: String {
    if let name = _displayName, !name.isEmpty {
      return name
    }
    if participants.count == 1 {
      return participants[0].displayName
    }
    if participants.isEmpty {
      return "Unknown"
    }
    let names = participants.prefix(3).map { $0.displayName }
    let suffix = participants.count > 3 ? " +\(participants.count - 3)" : ""
    return names.joined(separator: ", ") + suffix
  }

  /// Decoded group photo data from base64
  public var groupPhotoData: Data? {
    guard let groupPhotoBase64 = groupPhotoBase64 else { return nil }
    return Data(base64Encoded: groupPhotoBase64)
  }
}

// Custom Hashable/Equatable that includes id, unreadCount, and lastMessage
// to ensure SwiftUI detects changes to the conversation preview
extension Conversation: Hashable {
  public static func == (lhs: Conversation, rhs: Conversation) -> Bool {
    lhs.id == rhs.id && lhs.unreadCount == rhs.unreadCount
      && lhs.lastMessage?.id == rhs.lastMessage?.id
      && lhs.pinnedIndex == rhs.pinnedIndex
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(unreadCount)
    hasher.combine(lastMessage?.id)
    hasher.combine(pinnedIndex)
  }
}

// MARK: - Sync Warning Events

/// Event received when sync warning occurs (read status could not be synced to Messages.app)
public struct SyncWarningEvent: Codable, Sendable {
  public let conversationId: String
  public let message: String

  public init(conversationId: String, message: String) {
    self.conversationId = conversationId
    self.message = message
  }
}

/// Event received when sync warning is cleared (sync succeeded)
public struct SyncWarningClearedEvent: Codable, Sendable {
  public let conversationId: String

  public init(conversationId: String) {
    self.conversationId = conversationId
  }
}
