import XCTest

@testable import MessageBridgeClientCore

final class PlainTextRendererTests: XCTestCase {
  let renderer = PlainTextRenderer()

  func testId_isPlainText() {
    XCTAssertEqual(renderer.id, "plain-text")
  }

  func testPriority_isZero() {
    XCTAssertEqual(renderer.priority, 0)
  }

  func testCanRender_alwaysReturnsTrue() {
    let withText = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    let withNilText = Message(
      id: 2, guid: "g2", text: nil, date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    let emptyText = Message(
      id: 3, guid: "g3", text: "", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    XCTAssertTrue(renderer.canRender(withText))
    XCTAssertTrue(renderer.canRender(withNilText))
    XCTAssertTrue(renderer.canRender(emptyText))
  }
}
