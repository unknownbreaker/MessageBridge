import Foundation

/// Detects phone numbers in message text using NSDataDetector.
///
/// PhoneNumberDetector uses Apple's NSDataDetector to find phone numbers in
/// various formats (US, international, with/without parentheses, etc.) and
/// adds highlights for UI rendering.
///
/// ## Detection Examples
///
/// | Message | Detected |
/// |---------|----------|
/// | "Call me at 555-123-4567" | 555-123-4567 |
/// | "(555) 123-4567" | (555) 123-4567 |
/// | "+1-555-123-4567" | +1-555-123-4567 |
/// | "Home: 555-111-2222, Work: 555-333-4444" | Both numbers |
///
/// ## Priority
///
/// Priority 150 (primary enrichment) - runs after critical detection (codes)
/// but before secondary enrichment (emoji, formatting).
public struct PhoneNumberDetector: MessageProcessor {
  /// Unique identifier for this processor
  public let id = "phone-number-detector"

  /// Processing priority (150 = primary enrichment)
  public let priority = 150

  /// Cached NSDataDetector for phone numbers (expensive to create)
  // swiftlint:disable:next force_try
  private static let phoneDetector = try! NSDataDetector(
    types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
  )

  /// Creates a new PhoneNumberDetector instance.
  public init() {}

  /// Process the message to detect phone numbers.
  ///
  /// - Parameter message: The message to process
  /// - Returns: The message with detected phone numbers added as highlights
  public func process(_ message: ProcessedMessage) -> ProcessedMessage {
    guard let text = message.message.text else { return message }

    var result = message
    let range = NSRange(text.startIndex..., in: text)

    Self.phoneDetector.enumerateMatches(in: text, range: range) { match, _, _ in
      guard let match = match,
        let swiftRange = Range(match.range, in: text)
      else { return }

      let phone = String(text[swiftRange])
      let startIndex = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
      let endIndex = text.distance(from: text.startIndex, to: swiftRange.upperBound)

      result.highlights.append(
        TextHighlight(
          text: phone,
          startIndex: startIndex,
          endIndex: endIndex,
          type: .phoneNumber
        ))
    }

    return result
  }
}
