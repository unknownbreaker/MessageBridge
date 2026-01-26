import Foundation
import XCTest

@testable import MessageBridgeCore

final class PhoneNumberDetectorTests: XCTestCase {
  var detector: PhoneNumberDetector!

  override func setUp() {
    super.setUp()
    detector = PhoneNumberDetector()
  }

  override func tearDown() {
    detector = nil
    super.tearDown()
  }

  // MARK: - Basic Properties

  func testId() {
    XCTAssertEqual(detector.id, "phone-number-detector")
  }

  func testPriority() {
    XCTAssertEqual(detector.priority, 150)
  }

  // MARK: - Detection Cases (should detect)

  func testDetectsUSPhoneWithDashes() {
    let message = createTestMessage(text: "Call me at 555-123-4567")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!
    XCTAssertEqual(highlight.type, .phoneNumber)
    XCTAssertEqual(highlight.text, "555-123-4567")
  }

  func testDetectsPhoneWithParentheses() {
    let message = createTestMessage(text: "(555) 123-4567")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!
    XCTAssertEqual(highlight.type, .phoneNumber)
    XCTAssertEqual(highlight.text, "(555) 123-4567")
  }

  func testDetectsInternationalFormat() {
    let message = createTestMessage(text: "+1-555-123-4567")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!
    XCTAssertEqual(highlight.type, .phoneNumber)
    XCTAssertTrue(highlight.text.contains("555"))
  }

  func testDetectsMultiplePhones() {
    let message = createTestMessage(text: "Home: 555-111-2222, Work: 555-333-4444")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 2)

    let phones = result.highlights.map { $0.text }
    XCTAssertTrue(phones.contains("555-111-2222"))
    XCTAssertTrue(phones.contains("555-333-4444"))

    // All should be phone number type
    XCTAssertTrue(result.highlights.allSatisfy { $0.type == .phoneNumber })
  }

  // MARK: - Non-Detection Cases (should NOT detect)

  func testHandlesNilText() {
    let message = createTestMessage(text: nil)
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.highlights.isEmpty)
  }

  func testDoesNotDetectPlainText() {
    let message = createTestMessage(text: "Hello world!")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.highlights.isEmpty)
  }

  // MARK: - Index Tests

  func testCorrectIndicesForPhoneAtStart() {
    let message = createTestMessage(text: "555-123-4567 is my number")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!

    XCTAssertEqual(highlight.startIndex, 0)
    XCTAssertEqual(highlight.endIndex, 12)  // "555-123-4567" = 12 characters
    XCTAssertEqual(highlight.type, .phoneNumber)
  }

  func testCorrectIndicesForPhoneInMiddle() {
    let message = createTestMessage(text: "Call me at 555-123-4567 today")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!

    // "Call me at " = 11 characters
    XCTAssertEqual(highlight.startIndex, 11)
    // 11 + 12 = 23
    XCTAssertEqual(highlight.endIndex, 23)
    XCTAssertEqual(highlight.type, .phoneNumber)
  }

  func testCorrectIndicesForMultiplePhones() {
    let message = createTestMessage(text: "Home: 555-111-2222, Work: 555-333-4444")
    let result = detector.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 2)

    let home = result.highlights.first { $0.text == "555-111-2222" }!
    // "Home: " = 6 characters
    XCTAssertEqual(home.startIndex, 6)
    XCTAssertEqual(home.endIndex, 18)

    let work = result.highlights.first { $0.text == "555-333-4444" }!
    // "Home: 555-111-2222, Work: " = 26 characters
    XCTAssertEqual(work.startIndex, 26)
    XCTAssertEqual(work.endIndex, 38)
  }

  // MARK: - Preservation Tests

  func testPreservesExistingHighlights() {
    let message = createTestMessage(text: "Call 555-123-4567 about code")
    var processed = ProcessedMessage(message: message)
    processed.highlights = [
      TextHighlight(text: "code", startIndex: 23, endIndex: 27, type: .code)
    ]

    let result = detector.process(processed)

    // Should have both the existing highlight and the new phone highlight
    XCTAssertEqual(result.highlights.count, 2)
    XCTAssertTrue(result.highlights.contains { $0.type == .code })
    XCTAssertTrue(result.highlights.contains { $0.type == .phoneNumber })
  }

  func testPreservesExistingEnrichments() {
    let message = createTestMessage(text: "Call 555-123-4567")
    var processed = ProcessedMessage(message: message)
    processed.mentions = [Mention(text: "@test")]
    processed.isEmojiOnly = true
    processed.detectedCodes = [DetectedCode(value: "1234", confidence: .high)]

    let result = detector.process(processed)

    // Should preserve existing enrichments
    XCTAssertEqual(result.mentions.count, 1)
    XCTAssertTrue(result.isEmojiOnly)
    XCTAssertEqual(result.detectedCodes.count, 1)
    // And add new phone highlight
    XCTAssertEqual(result.highlights.count, 1)
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
