import Foundation

/// Detects verification/authentication codes (4-8 digits) in message text.
///
/// CodeDetector looks for numeric codes when context words suggest the message
/// contains a verification code (e.g., "Your verification code is 123456").
///
/// ## Detection Logic
///
/// 1. Checks if the message contains context words like "code", "verify", "OTP", etc.
/// 2. If context words are present, finds all 4-8 digit sequences
/// 3. Each detected code is added to `detectedCodes` with high confidence
/// 4. Corresponding highlights are added for UI rendering
///
/// ## Examples
///
/// | Message | Detected |
/// |---------|----------|
/// | "Your verification code is 847293" | 847293 (high) |
/// | "2FA code: 123456" | 123456 (high) |
/// | "I have 123456 items" | None (no context words) |
/// | "Your code is 123" | None (too short) |
///
/// ## Priority
///
/// Priority 200 (critical detection) - runs early to detect codes before
/// other processors that may use the highlights.
public struct CodeDetector: MessageProcessor {
  /// Unique identifier for this processor
  public let id = "code-detector"

  /// Processing priority (200 = critical detection, runs early)
  public let priority = 200

  /// Pre-compiled regex for 4-8 digit codes (compiled once, reused)
  // swiftlint:disable:next force_try
  private static let codeRegex = try! NSRegularExpression(pattern: #"\b(\d{4,8})\b"#)

  /// Context words that suggest a verification code is present
  private static let contextWords: Set<String> = [
    "code", "verify", "verification", "confirm", "otp",
    "pin", "password", "passcode", "2fa", "mfa",
    "security", "authentication", "login", "sign in",
  ]

  /// Creates a new CodeDetector instance.
  public init() {}

  /// Process the message to detect verification codes.
  ///
  /// - Parameter message: The message to process
  /// - Returns: The message with detected codes and highlights added
  public func process(_ message: ProcessedMessage) -> ProcessedMessage {
    guard let text = message.message.text else { return message }

    // Check for context words first (fast path for messages without verification context)
    let lowercased = text.lowercased()
    let hasContext = Self.contextWords.contains { lowercased.contains($0) }

    guard hasContext else { return message }

    var result = message
    let range = NSRange(text.startIndex..., in: text)
    let matches = Self.codeRegex.matches(in: text, range: range)

    for match in matches {
      guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }

      let code = String(text[swiftRange])
      result.detectedCodes.append(DetectedCode(value: code, confidence: .high))

      let startIndex = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
      let endIndex = text.distance(from: text.startIndex, to: swiftRange.upperBound)

      result.highlights.append(
        TextHighlight(
          text: code,
          startIndex: startIndex,
          endIndex: endIndex,
          type: .code
        ))
    }

    return result
  }
}
