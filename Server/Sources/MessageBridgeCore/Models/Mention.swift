import Foundation

/// Represents an @mention in message text
public struct Mention: Codable, Sendable, Equatable {
  /// The mention text including @ symbol (e.g., "@john")
  public let text: String

  /// Resolved phone number or email if available
  public let handle: String?

  public init(text: String, handle: String? = nil) {
    self.text = text
    self.handle = handle
  }
}
