import Foundation

/// Represents an @mention in message text.
///
/// Populated by the server's MentionExtractor processor.
public struct Mention: Codable, Sendable, Equatable, Hashable {
  /// The mention text including @ symbol (e.g., "@john")
  public let text: String

  /// Resolved phone number or email if available
  public let handle: String?

  public init(text: String, handle: String? = nil) {
    self.text = text
    self.handle = handle
  }
}
