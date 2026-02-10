import XCTest

@testable import MessageBridgeClientCore

final class HighlightedTextRendererTests: XCTestCase {
  let renderer = HighlightedTextRenderer()

  func testId() {
    XCTAssertEqual(renderer.id, "highlighted-text")
  }

  func testPriority() {
    XCTAssertEqual(renderer.priority, 90)
  }

  func testCanRender_withHighlights_true() {
    let highlights = [TextHighlight(text: "847293", type: .code)]
    let message = Message(
      id: 1, guid: "g1", text: "Code: 847293", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      highlights: highlights
    )
    XCTAssertTrue(renderer.canRender(message))
  }

  func testCanRender_nilHighlights_false() {
    let message = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1"
    )
    XCTAssertFalse(renderer.canRender(message))
  }

  func testCanRender_emptyHighlights_false() {
    let message = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      highlights: []
    )
    XCTAssertFalse(renderer.canRender(message))
  }

  func testCanRender_phoneNumberHighlight_true() {
    let highlights = [TextHighlight(text: "555-1234", type: .phoneNumber)]
    let message = Message(
      id: 1, guid: "g1", text: "Call 555-1234", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      highlights: highlights
    )
    XCTAssertTrue(renderer.canRender(message))
  }

  func testCanRender_mentionHighlight_true() {
    let highlights = [TextHighlight(text: "@john", type: .mention)]
    let message = Message(
      id: 1, guid: "g1", text: "Hey @john", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      highlights: highlights
    )
    XCTAssertTrue(renderer.canRender(message))
  }
}
