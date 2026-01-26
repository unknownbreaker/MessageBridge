import XCTest

@testable import MessageBridgeCore

final class ProcessedMessageTests: XCTestCase {

  // MARK: - Helper

  private func makeMessage(
    id: Int64 = 1,
    text: String? = "Test message"
  ) -> Message {
    Message(
      id: id,
      guid: "test-guid-\(id)",
      text: text,
      date: Date(),
      isFromMe: true,
      handleId: nil,
      conversationId: "chat-1"
    )
  }

  // MARK: - Initialization Tests

  func testInit_wrapsMessageWithEmptyEnrichments() {
    let message = makeMessage(id: 42, text: "Hello, world!")

    let processed = ProcessedMessage(message: message)

    XCTAssertEqual(processed.message.id, 42)
    XCTAssertEqual(processed.message.text, "Hello, world!")
    XCTAssertTrue(processed.detectedCodes.isEmpty)
    XCTAssertTrue(processed.highlights.isEmpty)
    XCTAssertTrue(processed.mentions.isEmpty)
    XCTAssertFalse(processed.isEmojiOnly)
  }

  // MARK: - Mutable Properties Tests

  func testDetectedCodes_canBeModified() {
    let message = makeMessage()
    var processed = ProcessedMessage(message: message)

    let code = DetectedCode(value: "123456", confidence: .high)
    processed.detectedCodes.append(code)

    XCTAssertEqual(processed.detectedCodes.count, 1)
    XCTAssertEqual(processed.detectedCodes[0].value, "123456")
    XCTAssertEqual(processed.detectedCodes[0].confidence, .high)
  }

  func testHighlights_canBeModified() {
    let message = makeMessage()
    var processed = ProcessedMessage(message: message)

    let highlight = TextHighlight(
      text: "123456",
      startIndex: 0,
      endIndex: 6,
      type: .code
    )
    processed.highlights.append(highlight)

    XCTAssertEqual(processed.highlights.count, 1)
    XCTAssertEqual(processed.highlights[0].text, "123456")
    XCTAssertEqual(processed.highlights[0].type, .code)
  }

  func testMentions_canBeModified() {
    let message = makeMessage()
    var processed = ProcessedMessage(message: message)

    let mention = Mention(text: "@john", handle: "+15551234567")
    processed.mentions.append(mention)

    XCTAssertEqual(processed.mentions.count, 1)
    XCTAssertEqual(processed.mentions[0].text, "@john")
    XCTAssertEqual(processed.mentions[0].handle, "+15551234567")
  }

  func testIsEmojiOnly_canBeModified() {
    let message = makeMessage(text: "😀")
    var processed = ProcessedMessage(message: message)

    XCTAssertFalse(processed.isEmojiOnly)

    processed.isEmojiOnly = true

    XCTAssertTrue(processed.isEmojiOnly)
  }

  // MARK: - Multiple Enrichments Tests

  func testMultipleEnrichments_canBeAdded() {
    let message = makeMessage(text: "Your code is 123456, @john sent it")
    var processed = ProcessedMessage(message: message)

    // Add multiple codes
    processed.detectedCodes.append(DetectedCode(value: "123456", confidence: .high))
    processed.detectedCodes.append(DetectedCode(value: "789012", confidence: .medium))

    // Add multiple highlights
    processed.highlights.append(
      TextHighlight(text: "123456", startIndex: 13, endIndex: 19, type: .code))
    processed.highlights.append(
      TextHighlight(text: "@john", startIndex: 21, endIndex: 26, type: .mention))

    // Add mention
    processed.mentions.append(Mention(text: "@john", handle: nil))

    XCTAssertEqual(processed.detectedCodes.count, 2)
    XCTAssertEqual(processed.highlights.count, 2)
    XCTAssertEqual(processed.mentions.count, 1)
  }

  // MARK: - Codable Tests

  func testCodable_encodesAndDecodes() throws {
    let message = makeMessage(id: 99, text: "Test encoding")
    var processed = ProcessedMessage(message: message)

    // Add enrichments
    processed.detectedCodes = [DetectedCode(value: "847293", confidence: .high)]
    processed.highlights = [TextHighlight(text: "847293", startIndex: 0, endIndex: 6, type: .code)]
    processed.mentions = [Mention(text: "@test", handle: "+15550001234")]
    processed.isEmojiOnly = false

    let encoder = JSONEncoder()
    let data = try encoder.encode(processed)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ProcessedMessage.self, from: data)

    XCTAssertEqual(decoded.message.id, 99)
    XCTAssertEqual(decoded.message.text, "Test encoding")
    XCTAssertEqual(decoded.detectedCodes.count, 1)
    XCTAssertEqual(decoded.detectedCodes[0].value, "847293")
    XCTAssertEqual(decoded.highlights.count, 1)
    XCTAssertEqual(decoded.highlights[0].text, "847293")
    XCTAssertEqual(decoded.mentions.count, 1)
    XCTAssertEqual(decoded.mentions[0].text, "@test")
    XCTAssertFalse(decoded.isEmojiOnly)
  }

  func testCodable_withEmptyEnrichments_encodesAndDecodes() throws {
    let message = makeMessage()
    let processed = ProcessedMessage(message: message)

    let encoder = JSONEncoder()
    let data = try encoder.encode(processed)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ProcessedMessage.self, from: data)

    XCTAssertTrue(decoded.detectedCodes.isEmpty)
    XCTAssertTrue(decoded.highlights.isEmpty)
    XCTAssertTrue(decoded.mentions.isEmpty)
    XCTAssertFalse(decoded.isEmojiOnly)
  }

  func testCodable_withIsEmojiOnlyTrue_encodesAndDecodes() throws {
    let message = makeMessage(text: "😀😀😀")
    var processed = ProcessedMessage(message: message)
    processed.isEmojiOnly = true

    let encoder = JSONEncoder()
    let data = try encoder.encode(processed)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ProcessedMessage.self, from: data)

    XCTAssertTrue(decoded.isEmojiOnly)
    XCTAssertEqual(decoded.message.text, "😀😀😀")
  }

  // MARK: - Sendable Tests

  func testSendable_canBeSentAcrossActors() async {
    let message = makeMessage()
    var processed = ProcessedMessage(message: message)
    processed.detectedCodes = [DetectedCode(value: "123456", confidence: .high)]

    // Use an actor to verify Sendable conformance
    let result = await withCheckedContinuation { continuation in
      Task.detached {
        // Accessing processed from a detached task verifies Sendable
        continuation.resume(returning: processed.detectedCodes.count)
      }
    }

    XCTAssertEqual(result, 1)
  }
}
