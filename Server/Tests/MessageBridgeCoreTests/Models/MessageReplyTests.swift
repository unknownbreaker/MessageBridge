import XCTest

@testable import MessageBridgeCore

final class MessageReplyTests: XCTestCase {

  private func makeMessage(
    replyToGuid: String? = nil,
    threadOriginatorGuid: String? = nil
  ) -> Message {
    Message(
      id: 1, guid: "msg-001", text: "Hello", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1",
      replyToGuid: replyToGuid,
      threadOriginatorGuid: threadOriginatorGuid
    )
  }

  func testMessage_replyFieldsDefaultToNil() {
    let msg = makeMessage()
    XCTAssertNil(msg.replyToGuid)
    XCTAssertNil(msg.threadOriginatorGuid)
  }

  func testMessage_replyFieldsStoreValues() {
    let msg = makeMessage(
      replyToGuid: "reply-guid",
      threadOriginatorGuid: "thread-guid"
    )
    XCTAssertEqual(msg.replyToGuid, "reply-guid")
    XCTAssertEqual(msg.threadOriginatorGuid, "thread-guid")
  }

  func testMessage_codableRoundTrip_withReplyFields() throws {
    let msg = makeMessage(
      replyToGuid: "reply-guid",
      threadOriginatorGuid: "thread-guid"
    )
    let data = try JSONEncoder().encode(msg)
    let decoded = try JSONDecoder().decode(Message.self, from: data)
    XCTAssertEqual(decoded.replyToGuid, "reply-guid")
    XCTAssertEqual(decoded.threadOriginatorGuid, "thread-guid")
  }

  func testMessage_codableRoundTrip_withoutReplyFields() throws {
    let msg = makeMessage()
    let data = try JSONEncoder().encode(msg)
    let decoded = try JSONDecoder().decode(Message.self, from: data)
    XCTAssertNil(decoded.replyToGuid)
    XCTAssertNil(decoded.threadOriginatorGuid)
  }
}
