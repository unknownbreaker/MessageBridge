import Foundation

/// Detects emoji-only messages for enlarged display in the client UI.
///
/// EmojiEnlarger checks if a message contains only emoji characters (with optional
/// whitespace) and a maximum of 5 emoji. When these conditions are met, the message
/// is marked for enlarged rendering in the client.
///
/// ## Detection Logic
///
/// 1. Trim whitespace from message text
/// 2. Check if all remaining characters are emoji
/// 3. Count the number of emoji (1-5 allowed)
/// 4. Set `isEmojiOnly = true` if both conditions pass
///
/// ## Examples
///
/// | Message | isEmojiOnly |
/// |---------|-------------|
/// | "👍" | true |
/// | "😀🎉" | true |
/// | "👍👍👍👍👍" | true (5 emoji) |
/// | "👍👍👍👍👍👍" | false (6 emoji) |
/// | "Hello 👍" | false (has text) |
/// | "👨‍👩‍👧‍👦" | true (family emoji counts as 1) |
///
/// ## Priority
///
/// Priority 50 (secondary enrichment) - runs after critical detection like codes.
public struct EmojiEnlarger: MessageProcessor {
  /// Unique identifier for this processor
  public let id = "emoji-enlarger"

  /// Processing priority (50 = secondary enrichment)
  public let priority = 50

  /// Maximum number of emoji for enlarged display
  private static let maxEmojiCount = 5

  /// Creates a new EmojiEnlarger instance.
  public init() {}

  /// Process the message to detect emoji-only content.
  ///
  /// - Parameter message: The message to process
  /// - Returns: The message with `isEmojiOnly` set appropriately
  public func process(_ message: ProcessedMessage) -> ProcessedMessage {
    guard let text = message.message.text else { return message }

    var result = message

    // Trim whitespace
    let trimmed = text.trimmingCharacters(in: .whitespaces)

    // Empty string is not emoji-only
    guard !trimmed.isEmpty else {
      result.isEmojiOnly = false
      return result
    }

    // Check if all characters are emoji
    let isAllEmoji = trimmed.allSatisfy { $0.isEmoji }

    // Count emoji (each grapheme cluster is one emoji)
    let emojiCount = trimmed.count

    // Only enlarge if 1-5 emoji
    result.isEmojiOnly = isAllEmoji && emojiCount <= Self.maxEmojiCount

    return result
  }
}

// MARK: - Character Extension for Emoji Detection

extension Character {
  /// Returns true if this character is an emoji.
  ///
  /// This handles various emoji types including:
  /// - Standard emoji (😀, 👍, etc.)
  /// - Emoji with skin tones (👋🏽)
  /// - ZWJ sequences (👨‍👩‍👧‍👦)
  /// - Flag emoji (🇺🇸)
  /// - Keycap sequences (1️⃣)
  var isEmoji: Bool {
    guard let scalar = unicodeScalars.first else { return false }

    // Check if it's a standard emoji or part of a sequence
    // The scalar must have emoji property and either:
    // - Has value > 0x238C (excludes basic symbols that have emoji presentation)
    // - Is part of a multi-scalar sequence (ZWJ, skin tones, etc.)
    return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
  }
}
