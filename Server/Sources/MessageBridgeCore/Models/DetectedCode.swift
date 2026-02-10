import Foundation

/// Represents a verification/authentication code detected in message text
public struct DetectedCode: Codable, Sendable, Equatable {
  /// The detected code value (e.g., "123456", "G-582941")
  public let value: String

  /// Confidence level of the detection
  public let confidence: Confidence

  /// Detection confidence levels
  public enum Confidence: String, Codable, Sendable {
    /// Context words + code pattern match
    case high
    /// Code pattern match only
    case medium
  }

  public init(value: String, confidence: Confidence) {
    self.value = value
    self.confidence = confidence
  }
}
