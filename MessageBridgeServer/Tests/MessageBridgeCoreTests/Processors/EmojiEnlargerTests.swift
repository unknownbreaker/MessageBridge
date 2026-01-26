import Foundation
import XCTest

@testable import MessageBridgeCore

final class EmojiEnlargerTests: XCTestCase {
  var enlarger: EmojiEnlarger!

  override func setUp() {
    super.setUp()
    enlarger = EmojiEnlarger()
  }

  override func tearDown() {
    enlarger = nil
    super.tearDown()
  }

  // MARK: - Basic Properties

  func testId() {
    XCTAssertEqual(enlarger.id, "emoji-enlarger")
  }

  func testPriority() {
    XCTAssertEqual(enlarger.priority, 50)
  }

  // MARK: - Emoji-only Detection (should set isEmojiOnly = true)

  func testSingleEmoji() {
    let message = createTestMessage(text: "👍")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  func testTwoEmojis() {
    let message = createTestMessage(text: "😀🎉")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  func testFiveEmojis() {
    let message = createTestMessage(text: "👍👍👍👍👍")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  func testEmojiWithWhitespace() {
    let message = createTestMessage(text: " 👍 ")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  func testMultiByteEmoji() {
    // Family emoji with ZWJ sequences
    let message = createTestMessage(text: "👨‍👩‍👧‍👦")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  func testSkinToneEmoji() {
    let message = createTestMessage(text: "👋🏽")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  func testFlagEmoji() {
    let message = createTestMessage(text: "🇺🇸")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  func testMixedEmojis() {
    let message = createTestMessage(text: "❤️🔥💯")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  // MARK: - Non Emoji-only (should set isEmojiOnly = false)

  func testSixEmojis() {
    let message = createTestMessage(text: "👍👍👍👍👍👍")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  func testTextAndEmojiMix() {
    let message = createTestMessage(text: "Hello 👍")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  func testOnlyText() {
    let message = createTestMessage(text: "Hello world")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  func testNilText() {
    let message = createTestMessage(text: nil)
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  func testEmptyString() {
    let message = createTestMessage(text: "")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  func testOnlyWhitespace() {
    let message = createTestMessage(text: "   ")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  func testOnlyNumbers() {
    let message = createTestMessage(text: "123")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  func testEmojiAtStartWithText() {
    let message = createTestMessage(text: "👍 Great job!")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  func testEmojiAtEndWithText() {
    let message = createTestMessage(text: "That's funny 😂")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertFalse(result.isEmojiOnly)
  }

  // MARK: - Preserves Other Fields

  func testPreservesExistingDetectedCodes() {
    let message = createTestMessage(text: "👍")
    var processed = ProcessedMessage(message: message)
    processed.detectedCodes = [DetectedCode(value: "123456", confidence: .high)]

    let result = enlarger.process(processed)

    XCTAssertTrue(result.isEmojiOnly)
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "123456")
  }

  func testPreservesExistingHighlights() {
    let message = createTestMessage(text: "👍")
    var processed = ProcessedMessage(message: message)
    processed.highlights = [
      TextHighlight(text: "test", startIndex: 0, endIndex: 4, type: .code)
    ]

    let result = enlarger.process(processed)

    XCTAssertTrue(result.isEmojiOnly)
    XCTAssertEqual(result.highlights.count, 1)
  }

  func testPreservesExistingMentions() {
    let message = createTestMessage(text: "👍")
    var processed = ProcessedMessage(message: message)
    processed.mentions = [Mention(text: "@test")]

    let result = enlarger.process(processed)

    XCTAssertTrue(result.isEmojiOnly)
    XCTAssertEqual(result.mentions.count, 1)
  }

  // MARK: - Edge Cases

  func testVariationSelectors() {
    // Heart with variation selector (text to emoji)
    let message = createTestMessage(text: "❤️")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
  }

  func testKeyCapEmoji() {
    // Keycap numbers should not be detected as regular numbers
    let message = createTestMessage(text: "1️⃣2️⃣3️⃣")
    let result = enlarger.process(ProcessedMessage(message: message))

    XCTAssertTrue(result.isEmojiOnly)
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
