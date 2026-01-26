import XCTest

@testable import MessageBridgeCore

final class MockMessageProcessorTests: XCTestCase {

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

  private func makeProcessedMessage(
    id: Int64 = 1,
    text: String? = "Test message"
  ) -> ProcessedMessage {
    ProcessedMessage(message: makeMessage(id: id, text: text))
  }

  // MARK: - Initialization Tests

  func testInit_setsIdAndPriority() {
    let processor = MockMessageProcessor(id: "test-id", priority: 42)

    XCTAssertEqual(processor.id, "test-id")
    XCTAssertEqual(processor.priority, 42)
  }

  func testInit_defaultHandlerReturnsMessageUnchanged() {
    let processor = MockMessageProcessor(id: "test", priority: 0)
    let input = makeProcessedMessage(id: 123, text: "Hello")

    let output = processor.process(input)

    XCTAssertEqual(output.message.id, 123)
    XCTAssertEqual(output.message.text, "Hello")
    XCTAssertTrue(output.detectedCodes.isEmpty)
    XCTAssertTrue(output.highlights.isEmpty)
    XCTAssertTrue(output.mentions.isEmpty)
    XCTAssertFalse(output.isEmojiOnly)
  }

  // MARK: - Custom Handler Tests

  func testProcessHandler_canBeCustomized() {
    var processor = MockMessageProcessor(id: "custom", priority: 100)
    processor.processHandler = { message in
      var modified = message
      modified.isEmojiOnly = true
      return modified
    }

    let input = makeProcessedMessage()
    let output = processor.process(input)

    XCTAssertTrue(output.isEmojiOnly)
  }

  func testProcessHandler_canAddDetectedCodes() {
    var processor = MockMessageProcessor(id: "code-detector", priority: 200)
    processor.processHandler = { message in
      var modified = message
      modified.detectedCodes = [
        DetectedCode(value: "123456", confidence: .high),
        DetectedCode(value: "ABCD12", confidence: .medium),
      ]
      return modified
    }

    let input = makeProcessedMessage()
    let output = processor.process(input)

    XCTAssertEqual(output.detectedCodes.count, 2)
    XCTAssertEqual(output.detectedCodes[0].value, "123456")
    XCTAssertEqual(output.detectedCodes[1].value, "ABCD12")
  }

  func testProcessHandler_canAddHighlights() {
    var processor = MockMessageProcessor(id: "highlighter", priority: 100)
    processor.processHandler = { message in
      var modified = message
      modified.highlights = [
        TextHighlight(text: "123456", startIndex: 0, endIndex: 6, type: .code),
        TextHighlight(text: "+15551234567", startIndex: 10, endIndex: 22, type: .phoneNumber),
      ]
      return modified
    }

    let input = makeProcessedMessage()
    let output = processor.process(input)

    XCTAssertEqual(output.highlights.count, 2)
    XCTAssertEqual(output.highlights[0].type, .code)
    XCTAssertEqual(output.highlights[1].type, .phoneNumber)
  }

  func testProcessHandler_canAddMentions() {
    var processor = MockMessageProcessor(id: "mention-extractor", priority: 100)
    processor.processHandler = { message in
      var modified = message
      modified.mentions = [
        Mention(text: "@john", handle: "+15551234567"),
        Mention(text: "@jane", handle: nil),
      ]
      return modified
    }

    let input = makeProcessedMessage()
    let output = processor.process(input)

    XCTAssertEqual(output.mentions.count, 2)
    XCTAssertEqual(output.mentions[0].text, "@john")
    XCTAssertEqual(output.mentions[0].handle, "+15551234567")
    XCTAssertEqual(output.mentions[1].text, "@jane")
    XCTAssertNil(output.mentions[1].handle)
  }

  // MARK: - Protocol Conformance Tests

  func testConformsToMessageProcessor() {
    let processor: any MessageProcessor = MockMessageProcessor(id: "test", priority: 50)

    XCTAssertEqual(processor.id, "test")
    XCTAssertEqual(processor.priority, 50)
  }

  func testConformsToIdentifiable() {
    let processor = MockMessageProcessor(id: "identifiable", priority: 0)

    // Identifiable requires id property
    let _: String = processor.id
  }

  func testConformsToSendable() async {
    let processor = MockMessageProcessor(id: "sendable", priority: 0)

    let result = await withCheckedContinuation { continuation in
      Task.detached {
        continuation.resume(returning: processor.priority)
      }
    }

    XCTAssertEqual(result, 0)
  }

  // MARK: - Struct Semantics Tests

  func testStruct_hasValueSemantics() {
    var processor1 = MockMessageProcessor(id: "original", priority: 100)
    processor1.processHandler = { message in
      var modified = message
      modified.isEmojiOnly = true
      return modified
    }

    var processor2 = processor1  // Copy
    processor2.processHandler = { message in
      var modified = message
      modified.detectedCodes = [DetectedCode(value: "999", confidence: .medium)]
      return modified
    }

    let input = makeProcessedMessage()

    // processor1 should still use its original handler
    let output1 = processor1.process(input)
    XCTAssertTrue(output1.isEmojiOnly)
    XCTAssertTrue(output1.detectedCodes.isEmpty)

    // processor2 uses its own handler
    let output2 = processor2.process(input)
    XCTAssertFalse(output2.isEmojiOnly)
    XCTAssertEqual(output2.detectedCodes.count, 1)
  }
}
