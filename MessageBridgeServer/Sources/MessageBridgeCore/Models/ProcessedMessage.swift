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

  /// Creates a new ProcessedMessage wrapping the given message with empty enrichments.
  ///
  /// - Parameter message: The original message to wrap
  public init(message: Message) {
    self.message = message
    self.detectedCodes = []
    self.highlights = []
    self.mentions = []
    self.isEmojiOnly = false
  }
}
