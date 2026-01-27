import XCTest

@testable import MessageBridgeClientCore

final class CopyCodeActionTests: XCTestCase {
  let action = CopyCodeAction()

  func testId() { XCTAssertEqual(action.id, "copy-code") }
  func testTitle() { XCTAssertEqual(action.title, "Copy Code") }
  func testIcon() { XCTAssertEqual(action.icon, "number.square") }
  func testNotDestructive() { XCTAssertFalse(action.destructive) }

  func testIsAvailable_withCodes_true() {
    let code = DetectedCode(value: "123456")
    let msg = Message(
      id: 1, guid: "g1", text: "Code: 123456", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1", detectedCodes: [code])
    XCTAssertTrue(action.isAvailable(for: msg))
  }

  func testIsAvailable_noCodes_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }

  func testIsAvailable_emptyCodes_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1", detectedCodes: [])
    XCTAssertFalse(action.isAvailable(for: msg))
  }
}
