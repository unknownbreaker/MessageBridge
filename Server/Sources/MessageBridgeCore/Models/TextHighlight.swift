import Foundation

/// Represents a highlighted region in message text
public struct TextHighlight: Codable, Sendable, Equatable {
  /// The highlighted text content
  public let text: String

  /// Start index in the original string (character offset)
  public let startIndex: Int

  /// End index in the original string (character offset, exclusive)
  public let endIndex: Int

  /// Type of highlight
  public let type: HighlightType

  /// Types of text highlights
  public enum HighlightType: String, Codable, Sendable {
    /// Verification/authentication code
    case code
    /// Phone number
    case phoneNumber
    /// @mention
    case mention
  }

  public init(text: String, startIndex: Int, endIndex: Int, type: HighlightType) {
    self.text = text
    self.startIndex = startIndex
    self.endIndex = endIndex
    self.type = type
  }
}
