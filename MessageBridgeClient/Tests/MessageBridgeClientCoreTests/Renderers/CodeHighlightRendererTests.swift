import XCTest

@testable import MessageBridgeClientCore

/// Tests that HighlightedTextRenderer handles code-highlight scenarios
/// previously covered by CodeHighlightRenderer.
final class CodeHighlightRendererTests: XCTestCase {
  let renderer = HighlightedTextRenderer()

  func testId_isHighlightedText() {
    XCTAssertEqual(renderer.id, "highlighted-text")
  }

  func testPriority_is90() {
    XCTAssertEqual(renderer.priority, 90)
  }

  func testCanRender_withCodeHighlights_returnsTrue() {
    let message = Message(
      id: 1, guid: "g1", text: "Your code is 847293", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      detectedCodes: [DetectedCode(value: "847293")],
      highlights: [TextHighlight(text: "847293", type: .code)]
    )
    XCTAssertTrue(renderer.canRender(message))
  }

  func testCanRender_withEmptyHighlights_returnsFalse() {
    let message = Message(
      id: 1, guid: "g1", text: "No codes", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      highlights: []
    )
    XCTAssertFalse(renderer.canRender(message))
  }

  func testCanRender_withNilHighlights_returnsFalse() {
    let message = Message(
      id: 1, guid: "g1", text: "No codes", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1"
    )
    XCTAssertFalse(renderer.canRender(message))
  }

  func testCanRender_withMultipleCodeHighlights_returnsTrue() {
    let message = Message(
      id: 1, guid: "g1", text: "Codes: 1234 and 5678", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      detectedCodes: [DetectedCode(value: "1234"), DetectedCode(value: "5678")],
      highlights: [
        TextHighlight(text: "1234", type: .code),
        TextHighlight(text: "5678", type: .code),
      ]
    )
    XCTAssertTrue(renderer.canRender(message))
  }
}
