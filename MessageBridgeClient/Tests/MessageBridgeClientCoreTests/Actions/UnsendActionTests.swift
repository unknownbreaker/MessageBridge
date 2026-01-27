import XCTest

@testable import MessageBridgeClientCore

final class UnsendActionTests: XCTestCase {
  let action = UnsendAction()

  func testId() { XCTAssertEqual(action.id, "unsend") }
  func testDestructive() { XCTAssertTrue(action.destructive) }

  func testIsAvailable_fromMe_true() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertTrue(action.isAvailable(for: msg))
  }

  func testIsAvailable_notFromMe_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }
}
