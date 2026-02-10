import Foundation

/// A highlight span in message text for rendering emphasis.
///
/// Used by renderers to apply visual styling to detected content
/// such as verification codes, URLs, phone numbers, and emails.
public struct TextHighlight: Codable, Sendable, Equatable, Hashable {
  /// The text content to highlight
  public let text: String

  /// The type of content detected
  public let type: HighlightType

  public enum HighlightType: String, Codable, Sendable {
    case code
    case link
    case phoneNumber
    case email
    case mention
  }

  public init(text: String, type: HighlightType) {
    self.text = text
    self.type = type
  }
}
