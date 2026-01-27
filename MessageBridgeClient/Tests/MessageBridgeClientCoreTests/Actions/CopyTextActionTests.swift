import XCTest

@testable import MessageBridgeClientCore

final class CopyTextActionTests: XCTestCase {
  let action = CopyTextAction()

  func testId() { XCTAssertEqual(action.id, "copy-text") }
  func testTitle() { XCTAssertEqual(action.title, "Copy") }
  func testIcon() { XCTAssertEqual(action.icon, "doc.on.doc") }
  func testNotDestructive() { XCTAssertFalse(action.destructive) }

  func testIsAvailable_withText_true() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertTrue(action.isAvailable(for: msg))
  }

  func testIsAvailable_nilText_false() {
    let msg = Message(
      id: 1, guid: "g1", text: nil, date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }

  func testIsAvailable_emptyText_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }
}
