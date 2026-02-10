import XCTest

@testable import MessageBridgeClientCore

final class ReplyPreviewDecoratorTests: XCTestCase {
  let decorator = ReplyPreviewDecorator()
  let context = DecoratorContext(
    isLastSentMessage: false, isLastMessage: false, conversationId: "chat1")

  func testId() {
    XCTAssertEqual(decorator.id, "replyPreview")
  }

  func testPosition_isTopLeading() {
    XCTAssertEqual(decorator.position, .topLeading)
  }

  func testShouldDecorate_returnsTrueWhenReplyToGuidPresent() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Reply", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1",
      replyToGuid: "original-guid"
    )
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_returnsFalseWhenNoReplyFields() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Normal", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1"
    )
    XCTAssertFalse(decorator.shouldDecorate(msg, context: context))
  }

  func testShouldDecorate_returnsTrueWhenThreadOriginatorGuidPresent() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Reply", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1",
      threadOriginatorGuid: "thread-guid"
    )
    XCTAssertTrue(decorator.shouldDecorate(msg, context: context))
  }
}
