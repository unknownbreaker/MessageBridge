import XCTest

@testable import MessageBridgeClientCore

final class MessageActionTests: XCTestCase {
  func testConformsToIdentifiable() {
    let action = MockMessageAction(id: "test")
    XCTAssertEqual(action.id, "test")
  }

  func testProperties() {
    let action = MockMessageAction(id: "a", title: "Copy", icon: "doc.on.doc", destructive: false)
    XCTAssertEqual(action.title, "Copy")
    XCTAssertEqual(action.icon, "doc.on.doc")
    XCTAssertFalse(action.destructive)
  }

  func testDestructiveAction() {
    let action = MockMessageAction(id: "del", title: "Delete", icon: "trash", destructive: true)
    XCTAssertTrue(action.destructive)
  }

  func testIsAvailable() {
    let action = MockMessageAction()
    let msg = makeMessage()
    XCTAssertTrue(action.isAvailable(for: msg))
    action.isAvailableResult = false
    XCTAssertFalse(action.isAvailable(for: msg))
  }

  func testPerform() async {
    let action = MockMessageAction()
    let msg = makeMessage()
    XCTAssertEqual(action.performCallCount, 0)
    await action.perform(on: msg)
    XCTAssertEqual(action.performCallCount, 1)
  }

  private func makeMessage() -> Message {
    Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
  }
}
