import XCTest

@testable import MessageBridgeClientCore

final class ReadReceiptDecoratorTests: XCTestCase {
  let decorator = ReadReceiptDecorator()

  func testId() {
    XCTAssertEqual(decorator.id, "read-receipt")
  }

  func testPosition_isBottomTrailing() {
    XCTAssertEqual(decorator.position, .bottomTrailing)
  }

  func testShouldDecorate_sentMessageAsLastSent_withDelivered_returnsTrue() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1", dateDelivered: Date())
    let context = DecoratorContext(
      isLastSentMessage: true, isLastMessage: true, conversationId: "c1")
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_sentMessageAsLastSent_withRead_returnsTrue() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1", dateRead: Date())
    let context = DecoratorContext(
      isLastSentMessage: true, isLastMessage: true, conversationId: "c1")
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_sentMessageNotLastSent_returnsFalse() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1", dateDelivered: Date())
    let context = DecoratorContext(
      isLastSentMessage: false, isLastMessage: false, conversationId: "c1")
    XCTAssertFalse(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_receivedMessage_returnsFalse() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1")
    let context = DecoratorContext(
      isLastSentMessage: false, isLastMessage: true, conversationId: "c1")
    XCTAssertFalse(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_sentAsLastSent_noDeliveryDates_returnsTrue() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    let context = DecoratorContext(
      isLastSentMessage: true, isLastMessage: true, conversationId: "c1")
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }
}
