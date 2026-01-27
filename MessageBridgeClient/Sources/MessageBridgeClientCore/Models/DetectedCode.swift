import Foundation

/// A detected verification/authentication code in a message.
///
/// Populated by the server's CodeDetector processor when it identifies
/// patterns like 2FA codes, OTPs, or verification numbers.
public struct DetectedCode: Codable, Sendable, Equatable {
  /// The code value (e.g., "847293", "G-582941")
  public let value: String

  public init(value: String) {
    self.value = value
  }
}
