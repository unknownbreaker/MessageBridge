import Foundation
import XCTest

@testable import MessageBridgeCore

final class MentionExtractorTests: XCTestCase {
  var extractor: MentionExtractor!

  override func setUp() {
    super.setUp()
    extractor = MentionExtractor()
  }

  override func tearDown() {
    extractor = nil
    super.tearDown()
  }

  // MARK: - Basic Properties

  func testId() {
    XCTAssertEqual(extractor.id, "mention-extractor")
  }

  func testPriority() {
    XCTAssertEqual(extractor.priority, 100)
  }

  // MARK: - Detection Cases (should detect)

  func testDetectsMentionInMiddle() {
    let message = createTestMessage(text: "Hey @john how are you?")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.mentions.count, 1)
    XCTAssertEqual(result.mentions.first?.text, "@john")
    XCTAssertNil(result.mentions.first?.handle)
  }

  func testDetectsMultipleMentions() {
    let message = createTestMessage(text: "@alice and @bob are here")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.mentions.count, 2)

    let mentionTexts = result.mentions.map { $0.text }
    XCTAssertTrue(mentionTexts.contains("@alice"))
    XCTAssertTrue(mentionTexts.contains("@bob"))
  }

  func testDetectsMentionAtStart() {
    let message = createTestMessage(text: "@test hello")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.mentions.count, 1)
    XCTAssertEqual(result.mentions.first?.text, "@test")
  }

  func testDetectsMentionAtEnd() {
    let message = createTestMessage(text: "Hello @world")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.mentions.count, 1)
    XCTAssertEqual(result.mentions.first?.text, "@world")
  }

  func testDetectsMentionWithUnderscore() {
    let message = createTestMessage(text: "Hey @john_doe")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.mentions.count, 1)
    XCTAssertEqual(result.mentions.first?.text, "@john_doe")
  }

  func testDetectsMentionWithNumbers() {
    let message = createTestMessage(text: "Thanks @user123")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.mentions.count, 1)
    XCTAssertEqual(result.mentions.first?.text, "@user123")
  }

  // MARK: - Non-Detection Cases (should NOT detect)

  func testHandlesNilText() {
    let message = createTestMessage(text: nil)
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.mentions.isEmpty)
    XCTAssertTrue(result.highlights.isEmpty)
  }

  func testDoesNotDetectPlainText() {
    let message = createTestMessage(text: "Hello world!")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.mentions.isEmpty)
    XCTAssertTrue(result.highlights.isEmpty)
  }

  // MARK: - Index Tests

  func testCorrectIndicesForMentionAtStart() {
    let message = createTestMessage(text: "@test hello")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!

    XCTAssertEqual(highlight.startIndex, 0)
    XCTAssertEqual(highlight.endIndex, 5)  // "@test" = 5 characters
    XCTAssertEqual(highlight.type, .mention)
  }

  func testCorrectIndicesForMentionInMiddle() {
    let message = createTestMessage(text: "Hey @john how are you?")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    let highlight = result.highlights.first!

    // "Hey " = 4 characters
    XCTAssertEqual(highlight.startIndex, 4)
    // 4 + 5 (@john) = 9
    XCTAssertEqual(highlight.endIndex, 9)
    XCTAssertEqual(highlight.type, .mention)
  }

  func testCorrectIndicesForMultipleMentions() {
    let message = createTestMessage(text: "@alice and @bob")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 2)

    let alice = result.highlights.first { $0.text == "@alice" }!
    XCTAssertEqual(alice.startIndex, 0)
    XCTAssertEqual(alice.endIndex, 6)

    let bob = result.highlights.first { $0.text == "@bob" }!
    // "@alice and " = 11 characters
    XCTAssertEqual(bob.startIndex, 11)
    XCTAssertEqual(bob.endIndex, 15)
  }

  func testHighlightTypeIsMention() {
    let message = createTestMessage(text: "Hey @user")
    let result = extractor.process(ProcessedMessage(message: message))

    XCTAssertEqual(result.highlights.count, 1)
    XCTAssertEqual(result.highlights.first?.type, .mention)
  }

  // MARK: - Preservation Tests

  func testPreservesExistingHighlights() {
    let message = createTestMessage(text: "Hey @john call 555-123-4567")
    var processed = ProcessedMessage(message: message)
    processed.highlights = [
      TextHighlight(text: "555-123-4567", startIndex: 15, endIndex: 27, type: .phoneNumber)
    ]

    let result = extractor.process(processed)

    // Should have both the existing highlight and the new mention highlight
    XCTAssertEqual(result.highlights.count, 2)
    XCTAssertTrue(result.highlights.contains { $0.type == .phoneNumber })
    XCTAssertTrue(result.highlights.contains { $0.type == .mention })
  }

  func testPreservesExistingEnrichments() {
    let message = createTestMessage(text: "Hey @user")
    var processed = ProcessedMessage(message: message)
    processed.isEmojiOnly = true
    processed.detectedCodes = [DetectedCode(value: "1234", confidence: .high)]

    let result = extractor.process(processed)

    // Should preserve existing enrichments
    XCTAssertTrue(result.isEmojiOnly)
    XCTAssertEqual(result.detectedCodes.count, 1)
    // And add new mention
    XCTAssertEqual(result.mentions.count, 1)
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
