import Foundation

/// Extracts @mentions from message text using regex.
///
/// MentionExtractor uses a regex pattern to find @mentions in message text.
/// Mentions must start with @ followed by one or more word characters
/// (letters, digits, or underscores).
///
/// ## Detection Examples
///
/// | Message | Detected |
/// |---------|----------|
/// | "Hey @john how are you?" | @john |
/// | "@alice and @bob are here" | @alice, @bob |
/// | "@test hello" | @test |
/// | "Hello @world" | @world |
/// | "Hey @john_doe" | @john_doe |
/// | "Thanks @user123" | @user123 |
///
/// ## Priority
///
/// Priority 100 (primary enrichment) - runs after critical detection (codes)
/// but with other primary enrichments (links, phone numbers).
public struct MentionExtractor: MessageProcessor {
  /// Unique identifier for this processor
  public let id = "mention-extractor"

  /// Processing priority (100 = primary enrichment)
  public let priority = 100

  /// Pre-compiled regex for @mentions
  /// Matches @ followed by one or more word characters (letters, digits, underscore)
  // swiftlint:disable:next force_try
  private static let mentionRegex = try! NSRegularExpression(pattern: #"@(\w+)"#)

  /// Creates a new MentionExtractor instance.
  public init() {}

  /// Process the message to extract @mentions.
  ///
  /// - Parameter message: The message to process
  /// - Returns: The message with detected mentions and highlights added
  public func process(_ message: ProcessedMessage) -> ProcessedMessage {
    guard let text = message.message.text else { return message }

    var result = message

    let range = NSRange(text.startIndex..., in: text)
    let matches = Self.mentionRegex.matches(in: text, range: range)

    for match in matches {
      guard let swiftRange = Range(match.range, in: text) else { continue }

      let mention = String(text[swiftRange])
      let startIndex = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
      let endIndex = text.distance(from: text.startIndex, to: swiftRange.upperBound)

      result.mentions.append(Mention(text: mention, handle: nil))
      result.highlights.append(
        TextHighlight(
          text: mention,
          startIndex: startIndex,
          endIndex: endIndex,
          type: .mention
        ))
    }

    return result
  }
}
