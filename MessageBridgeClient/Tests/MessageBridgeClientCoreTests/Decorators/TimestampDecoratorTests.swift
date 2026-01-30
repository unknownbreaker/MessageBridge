import XCTest

@testable import MessageBridgeClientCore

final class TimestampDecoratorTests: XCTestCase {
  let decorator = TimestampDecorator()
  let context = DecoratorContext(
    isLastSentMessage: false, isLastMessage: false, conversationId: "c1")

  func testId() { XCTAssertEqual(decorator.id, "timestamp") }
  func testPosition_isBelow() { XCTAssertEqual(decorator.position, .below) }

  func testShouldDecorate_alwaysTrue() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_nilText_stillTrue() {
    let msg = Message(
      id: 1, guid: "g1", text: nil, date: Date(), isFromMe: false, handleId: 1, conversationId: "c1"
    )
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }
}
