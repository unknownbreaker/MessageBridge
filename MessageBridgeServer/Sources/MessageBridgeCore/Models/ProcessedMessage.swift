import Foundation

/// Wraps a Message with enrichment fields populated by message processors.
///
/// The original message remains immutable while enrichment fields can be
/// modified as the message flows through the processor chain.
public struct ProcessedMessage: Codable, Sendable {
  /// The original message from the database
  public let message: Message

  /// Detected verification/2FA codes
  public var detectedCodes: [DetectedCode]

  /// Text highlights (codes, phone numbers, mentions, etc.)
  public var highlights: [TextHighlight]

  /// Detected @mentions
  public var mentions: [Mention]

  /// Whether this is an emoji-only message (for enlarged display)
  public var isEmojiOnly: Bool

  /// Tapbacks on this message (copied from underlying message for convenience)
  public var tapbacks: [Tapback]

  /// Creates a new ProcessedMessage wrapping the given message with empty enrichments.
  ///
  /// - Parameter message: The original message to wrap
  public init(message: Message) {
    self.message = message
    self.detectedCodes = []
    self.highlights = []
    self.mentions = []
    self.isEmojiOnly = false
    self.tapbacks = message.tapbacks
  }

  // MARK: - Convenience Accessors

  /// Message ID (forwards to underlying message)
  public var id: Int64 { message.id }

  /// Conversation ID (forwards to underlying message)
  public var conversationId: String { message.conversationId }

  /// Message text (forwards to underlying message)
  public var text: String? { message.text }

  /// Message date (forwards to underlying message)
  public var date: Date { message.date }

  /// Whether the message is from the current user (forwards to underlying message)
  public var isFromMe: Bool { message.isFromMe }

  /// Whether the message has attachments (forwards to underlying message)
  public var hasAttachments: Bool { message.hasAttachments }

  /// Message GUID (forwards to underlying message)
  public var guid: String { message.guid }

  /// Handle ID (forwards to underlying message)
  public var handleId: Int64? { message.handleId }

  /// Attachments (forwards to underlying message)
  public var attachments: [Attachment] { message.attachments }
}
