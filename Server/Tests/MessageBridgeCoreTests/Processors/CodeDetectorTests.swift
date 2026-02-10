import Foundation
import XCTest

@testable import MessageBridgeCore

final class CodeDetectorTests: XCTestCase {
  var detector: CodeDetector!

  override func setUp() {
    super.setUp()
    detector = CodeDetector()
  }

  override func tearDown() {
    detector = nil
    super.tearDown()
  }

  // MARK: - Basic Properties

  func testId() {
    XCTAssertEqual(detector.id, "code-detector")
  }

  func testPriority() {
    XCTAssertEqual(detector.priority, 200)
  }

  // MARK: - Detection Cases (should detect)

  func testDetectsVerificationCode() {
    let message = createTestMessage(text: "Your verification code is 847293")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "847293")
    XCTAssertEqual(result.detectedCodes.first?.confidence, .high)
  }

  func testDetects4DigitCode() {
    let message = createTestMessage(text: "Your Uber code: 8472")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "8472")
    XCTAssertEqual(result.detectedCodes.first?.confidence, .high)
  }

  func testDetects8DigitCode() {
    let message = createTestMessage(text: "Security code: 12345678")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "12345678")
    XCTAssertEqual(result.detectedCodes.first?.confidence, .high)
  }

  func testDetectsWithOTPKeyword() {
    let message = createTestMessage(text: "Your OTP is 567890")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "567890")
    XCTAssertEqual(result.detectedCodes.first?.confidence, .high)
  }

  func testDetectsWith2FAKeyword() {
    let message = createTestMessage(text: "2FA code: 123456")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "123456")
    XCTAssertEqual(result.detectedCodes.first?.confidence, .high)
  }

  func testDetectsWithLoginKeyword() {
    let message = createTestMessage(text: "Use 987654 to login")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "987654")
    XCTAssertEqual(result.detectedCodes.first?.confidence, .high)
  }

  func testCaseInsensitiveContextWords() {
    let message = createTestMessage(text: "VERIFICATION CODE: 123456")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "123456")
    XCTAssertEqual(result.detectedCodes.first?.confidence, .high)
  }

  func testDetectsMultipleCodes() {
    let message = createTestMessage(text: "Verify with 1234 or confirm with 5678")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.detectedCodes.count, 2)
    let values = result.detectedCodes.map { $0.value }
    XCTAssertTrue(values.contains("1234"))
    XCTAssertTrue(values.contains("5678"))
  }

  // MARK: - Non-Detection Cases (should NOT detect)

  func testDoesNotDetectWithoutContextWords() {
    let message = createTestMessage(text: "I have 123456 items")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testDoesNotDetectNonDigitCode() {
    let message = createTestMessage(text: "Use code SAVE20 for 20% off")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testDoesNotDetectPhoneNumber() {
    let message = createTestMessage(text: "Call me at 555-1234")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testHandlesNilText() {
    let message = createTestMessage(text: nil)
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.detectedCodes.isEmpty)
    XCTAssertTrue(result.highlights.isEmpty)
  }

  func testDoesNotDetectTooShortCode() {
    let message = createTestMessage(text: "Your code is 123")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testDoesNotDetectTooLongCode() {
    let message = createTestMessage(text: "Your code is 123456789")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  // MARK: - Highlight Tests

  func testAddsHighlightWithCorrectIndices() {
    let message = createTestMessage(text: "Your verification code is 847293")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!

    XCTAssertEqual(highlight.text, "847293")
    XCTAssertEqual(highlight.type, .code)
    // "Your verification code is " = 26 characters
    XCTAssertEqual(highlight.startIndex, 26)
    // "847293" = 6 characters, so end is 26 + 6 = 32
    XCTAssertEqual(highlight.endIndex, 32)
  }

  func testHighlightIndicesForCodeAtStart() {
    let message = createTestMessage(text: "1234 is your code")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!

    XCTAssertEqual(highlight.startIndex, 0)
    XCTAssertEqual(highlight.endIndex, 4)
  }

  func testHighlightIndicesForMultipleCodes() {
    let message = createTestMessage(text: "Verify 1234 or confirm 5678")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 2)

    // "Verify " = 7 characters
    let highlight1 = result.highlights.first { $0.text == "1234" }!
    XCTAssertEqual(highlight1.startIndex, 7)
    XCTAssertEqual(highlight1.endIndex, 11)

    // "Verify 1234 or confirm " = 23 characters
    let highlight2 = result.highlights.first { $0.text == "5678" }!
    XCTAssertEqual(highlight2.startIndex, 23)
    XCTAssertEqual(highlight2.endIndex, 27)
  }

  func testHighlightTypeIsCode() {
    let message = createTestMessage(text: "Your verification code is 847293")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.first?.type, .code)
  }

  // MARK: - Edge Cases

  func testPreservesExistingEnrichments() {
    let message = createTestMessage(text: "Your verification code is 847293")
    var processed = ProcessedMessage(message: message)
    processed.mentions = [Mention(text: "@test")]
    processed.isEmojiOnly = true

    let result = detector.process(processed)

    // Should preserve existing enrichments
    XCTAssertEqual(result.mentions.count, 1)
    XCTAssertTrue(result.isEmojiOnly)
    // And add new ones
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.highlights.count, 1)
  }

  func testAccumulatesWithExistingHighlights() {
    let message = createTestMessage(text: "Your verification code is 847293")
    var processed = ProcessedMessage(message: message)
    processed.highlights = [
      TextHighlight(text: "@mention", startIndex: 0, endIndex: 8, type: .mention)
    ]

    let result = detector.process(processed)

    XCTAssertEqual(result.highlights.count, 2)
  }

  // MARK: - Helpers

  private func createTestMessage(text: String?) -> Message {
    Message(
      id: 1,
      guid: "test-guid",
      text: text,
      date: Date(),
      isFromMe: false,
      handleId: 1,
      conversationId: "chat123",
      attachments: []
    )
  }
}
