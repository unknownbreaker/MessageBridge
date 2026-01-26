import XCTest

@testable import MessageBridgeCore

final class MessageProcessorTests: XCTestCase {

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

  // MARK: - Protocol Requirements Tests

  func testProtocol_hasRequiredIdProperty() {
    let processor = MockMessageProcessor(id: "test-processor", priority: 100)

    XCTAssertEqual(processor.id, "test-processor")
  }

  func testProtocol_hasRequiredPriorityProperty() {
    let processor = MockMessageProcessor(id: "test-processor", priority: 100)

    XCTAssertEqual(processor.priority, 100)
  }

  func testProtocol_identifiableUsesId() {
    let processor1 = MockMessageProcessor(id: "processor-a", priority: 50)
    let processor2 = MockMessageProcessor(id: "processor-b", priority: 50)

    // Identifiable should use id for identity
    XCTAssertNotEqual(processor1.id, processor2.id)
  }

  // MARK: - Process Method Tests

  func testProcess_canReturnModifiedMessage() {
    var processor = MockMessageProcessor(id: "code-detector", priority: 100)

    // Configure mock to add a detected code
    processor.processHandler = { message in
      var modified = message
      modified.detectedCodes = [DetectedCode(value: "123456", confidence: .high)]
      return modified
    }

    let input = makeProcessedMessage(text: "Your code is 123456")
    let output = processor.process(input)

    XCTAssertEqual(output.detectedCodes.count, 1)
    XCTAssertEqual(output.detectedCodes[0].value, "123456")
  }

  func testProcess_canReturnUnmodifiedMessage_passthrough() {
    let processor = MockMessageProcessor(id: "passthrough", priority: 0)
    // Default handler returns message unchanged

    let input = makeProcessedMessage(text: "Hello, world!")
    let output = processor.process(input)

    // Should be unchanged (passthrough behavior)
    XCTAssertEqual(output.message.text, input.message.text)
    XCTAssertEqual(output.message.id, input.message.id)
    XCTAssertTrue(output.detectedCodes.isEmpty)
    XCTAssertTrue(output.highlights.isEmpty)
    XCTAssertTrue(output.mentions.isEmpty)
    XCTAssertFalse(output.isEmojiOnly)
  }

  func testProcess_preservesOriginalMessage() {
    var processor = MockMessageProcessor(id: "enricher", priority: 50)

    processor.processHandler = { message in
      var modified = message
      modified.isEmojiOnly = true
      return modified
    }

    let input = makeProcessedMessage(id: 42, text: "Hello")
    let output = processor.process(input)

    // Original message should be preserved
    XCTAssertEqual(output.message.id, 42)
    XCTAssertEqual(output.message.text, "Hello")
    // But enrichment should be added
    XCTAssertTrue(output.isEmojiOnly)
  }

  // MARK: - Multiple Enrichments Tests

  func testProcess_canAddMultipleEnrichments() {
    var processor = MockMessageProcessor(id: "full-enricher", priority: 100)

    processor.processHandler = { message in
      var modified = message
      modified.detectedCodes = [
        DetectedCode(value: "123456", confidence: .high),
        DetectedCode(value: "789012", confidence: .medium),
      ]
      modified.highlights = [
        TextHighlight(text: "123456", startIndex: 0, endIndex: 6, type: .code)
      ]
      modified.mentions = [
        Mention(text: "@john", handle: "+15551234567")
      ]
      return modified
    }

    let input = makeProcessedMessage()
    let output = processor.process(input)

    XCTAssertEqual(output.detectedCodes.count, 2)
    XCTAssertEqual(output.highlights.count, 1)
    XCTAssertEqual(output.mentions.count, 1)
  }

  // MARK: - Priority Tests

  func testPriority_higherValueMeansHigherPriority() {
    let lowPriority = MockMessageProcessor(id: "low", priority: 0)
    let mediumPriority = MockMessageProcessor(id: "medium", priority: 50)
    let highPriority = MockMessageProcessor(id: "high", priority: 100)

    // Create array and sort by priority descending (higher first)
    let processors = [lowPriority, mediumPriority, highPriority]
    let sorted = processors.sorted { $0.priority > $1.priority }

    XCTAssertEqual(sorted[0].id, "high")
    XCTAssertEqual(sorted[1].id, "medium")
    XCTAssertEqual(sorted[2].id, "low")
  }

  func testPriority_canBeNegative() {
    let processor = MockMessageProcessor(id: "fallback", priority: -100)

    XCTAssertEqual(processor.priority, -100)
  }

  func testPriority_canBeZero() {
    let processor = MockMessageProcessor(id: "default", priority: 0)

    XCTAssertEqual(processor.priority, 0)
  }

  // MARK: - Sendable Tests

  func testSendable_processorCanBeSentAcrossActors() async {
    let processor = MockMessageProcessor(id: "sendable-test", priority: 50)

    let result = await withCheckedContinuation { continuation in
      Task.detached {
        // Accessing processor from detached task verifies Sendable
        continuation.resume(returning: processor.id)
      }
    }

    XCTAssertEqual(result, "sendable-test")
  }

  // MARK: - Identifiable Tests

  func testIdentifiable_conformsToIdentifiable() {
    let processor = MockMessageProcessor(id: "identifiable-test", priority: 0)

    // The id property satisfies Identifiable requirement
    let _: String = processor.id

    // Can be used in contexts requiring Identifiable
    let processors: [any MessageProcessor] = [processor]
    XCTAssertEqual(processors.count, 1)
  }
}
