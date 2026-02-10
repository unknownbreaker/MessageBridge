import XCTest

@testable import MessageBridgeClientCore

final class MessageReplyClientTests: XCTestCase {

  func testMessage_replyFieldsDefaultToNil() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Hello", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1"
    )
    XCTAssertNil(msg.replyToGuid)
    XCTAssertNil(msg.threadOriginatorGuid)
  }

  func testMessage_replyFieldsStoreValues() {
    let msg = Message(
      id: 1, guid: "msg-001", text: "Hello", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "chat1",
      replyToGuid: "reply-guid",
      threadOriginatorGuid: "thread-guid"
    )
    XCTAssertEqual(msg.replyToGuid, "reply-guid")
    XCTAssertEqual(msg.threadOriginatorGuid, "thread-guid")
  }

  func testMessage_decodesReplyFieldsFromJSON() throws {
    let json = """
      {
        "id": 1, "guid": "msg-001", "text": "Reply text",
        "date": 0, "isFromMe": false, "handleId": 1,
        "conversationId": "chat1", "attachments": [],
        "replyToGuid": "original-guid",
        "threadOriginatorGuid": "thread-root-guid"
      }
      """.data(using: .utf8)!

    let msg = try JSONDecoder().decode(Message.self, from: json)
    XCTAssertEqual(msg.replyToGuid, "original-guid")
    XCTAssertEqual(msg.threadOriginatorGuid, "thread-root-guid")
  }

  func testMessage_decodesWithoutReplyFields() throws {
    let json = """
      {
        "id": 1, "guid": "msg-001", "text": "Plain text",
        "date": 0, "isFromMe": false, "handleId": 1,
        "conversationId": "chat1", "attachments": []
      }
      """.data(using: .utf8)!

    let msg = try JSONDecoder().decode(Message.self, from: json)
    XCTAssertNil(msg.replyToGuid)
    XCTAssertNil(msg.threadOriginatorGuid)
  }
}
