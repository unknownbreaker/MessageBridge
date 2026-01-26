import Foundation
import XCTest

@testable import MessageBridgeCore

final class ProcessorChainTests: XCTestCase {
  override func setUp() {
    super.setUp()
    ProcessorChain.shared.reset()
  }

  override func tearDown() {
    ProcessorChain.shared.reset()
    super.tearDown()
  }

  // MARK: - Singleton Tests

  func testSharedReturnsSameInstance() {
    let instance1 = ProcessorChain.shared
    let instance2 = ProcessorChain.shared

    XCTAssertTrue(instance1 === instance2, "shared should always return the same instance")
  }

  // MARK: - Registration Tests

  func testRegisterAddsProcessor() {
    let processor = MockMessageProcessor(id: "test", priority: 100)

    ProcessorChain.shared.register(processor)

    XCTAssertEqual(ProcessorChain.shared.all.count, 1)
    XCTAssertEqual(ProcessorChain.shared.all.first?.id, "test")
  }

  func testRegisterSortsByPriorityDescending() {
    let lowPriority = MockMessageProcessor(id: "low", priority: 10)
    let midPriority = MockMessageProcessor(id: "mid", priority: 50)
    let highPriority = MockMessageProcessor(id: "high", priority: 100)

    // Register in non-sorted order
    ProcessorChain.shared.register(midPriority)
    ProcessorChain.shared.register(lowPriority)
    ProcessorChain.shared.register(highPriority)

    let ids = ProcessorChain.shared.all.map { $0.id }
    XCTAssertEqual(
      ids, ["high", "mid", "low"], "Processors should be sorted by priority descending")
  }

  func testRegisterMultipleProcessorsWithSamePriority() {
    let processor1 = MockMessageProcessor(id: "first", priority: 100)
    let processor2 = MockMessageProcessor(id: "second", priority: 100)

    ProcessorChain.shared.register(processor1)
    ProcessorChain.shared.register(processor2)

    XCTAssertEqual(ProcessorChain.shared.all.count, 2)
    // Both should be present (stable sort maintains insertion order for equal priorities)
    let ids = Set(ProcessorChain.shared.all.map { $0.id })
    XCTAssertTrue(ids.contains("first"))
    XCTAssertTrue(ids.contains("second"))
  }

  // MARK: - Processing Tests

  func testProcessRunsAllProcessorsInOrder() {
    var executionOrder: [String] = []

    var highProcessor = MockMessageProcessor(id: "high", priority: 100)
    highProcessor.processHandler = { msg in
      executionOrder.append("high")
      return msg
    }

    var lowProcessor = MockMessageProcessor(id: "low", priority: 10)
    lowProcessor.processHandler = { msg in
      executionOrder.append("low")
      return msg
    }

    var midProcessor = MockMessageProcessor(id: "mid", priority: 50)
    midProcessor.processHandler = { msg in
      executionOrder.append("mid")
      return msg
    }

    ProcessorChain.shared.register(lowProcessor)
    ProcessorChain.shared.register(highProcessor)
    ProcessorChain.shared.register(midProcessor)

    let message = createTestMessage()
    _ = ProcessorChain.shared.process(message)

    XCTAssertEqual(
      executionOrder, ["high", "mid", "low"], "Processors should run in priority order")
  }

  func testProcessAccumulatesEnrichments() {
    var codeProcessor = MockMessageProcessor(id: "code", priority: 100)
    codeProcessor.processHandler = { msg in
      var modified = msg
      modified.detectedCodes = [DetectedCode(value: "123456", confidence: .high)]
      return modified
    }

    var mentionProcessor = MockMessageProcessor(id: "mention", priority: 50)
    mentionProcessor.processHandler = { msg in
      var modified = msg
      modified.mentions = [Mention(text: "@test")]
      return modified
    }

    var emojiProcessor = MockMessageProcessor(id: "emoji", priority: 10)
    emojiProcessor.processHandler = { msg in
      var modified = msg
      modified.isEmojiOnly = true
      return modified
    }

    ProcessorChain.shared.register(codeProcessor)
    ProcessorChain.shared.register(mentionProcessor)
    ProcessorChain.shared.register(emojiProcessor)

    let message = createTestMessage()
    let result = ProcessorChain.shared.process(message)

    // All enrichments should be accumulated
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "123456")
    XCTAssertEqual(result.mentions.count, 1)
    XCTAssertEqual(result.mentions.first?.text, "@test")
    XCTAssertTrue(result.isEmojiOnly)
  }

  func testProcessWithNoProcessorsReturnsBaseProcessedMessage() {
    let message = createTestMessage()
    let result = ProcessorChain.shared.process(message)

    // Should return ProcessedMessage with original message and empty enrichments
    XCTAssertEqual(result.message.id, message.id)
    XCTAssertEqual(result.message.text, message.text)
    XCTAssertTrue(result.detectedCodes.isEmpty)
    XCTAssertTrue(result.highlights.isEmpty)
    XCTAssertTrue(result.mentions.isEmpty)
    XCTAssertFalse(result.isEmojiOnly)
  }

  // MARK: - Reset Tests

  func testResetClearsAllProcessors() {
    ProcessorChain.shared.register(MockMessageProcessor(id: "test1", priority: 100))
    ProcessorChain.shared.register(MockMessageProcessor(id: "test2", priority: 50))

    XCTAssertEqual(ProcessorChain.shared.all.count, 2)

    ProcessorChain.shared.reset()

    XCTAssertEqual(ProcessorChain.shared.all.count, 0)
  }

  // MARK: - Helpers

  private func createTestMessage(text: String = "Test message") -> Message {
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
