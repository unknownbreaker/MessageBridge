import XCTest

@testable import MessageBridgeClientCore

final class CodeHighlightRendererTests: XCTestCase {
  let renderer = CodeHighlightRenderer()

  func testId_isCodeHighlight() {
    XCTAssertEqual(renderer.id, "code-highlight")
  }

  func testPriority_is100() {
    XCTAssertEqual(renderer.priority, 100)
  }

  func testCanRender_withDetectedCodes_returnsTrue() {
    let message = Message(
      id: 1, guid: "g1", text: "Your code is 847293", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      attachments: [],
      detectedCodes: [DetectedCode(value: "847293")]
    )
    XCTAssertTrue(renderer.canRender(message))
  }

  func testCanRender_withEmptyCodes_returnsFalse() {
    let message = Message(
      id: 1, guid: "g1", text: "No codes", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      attachments: [],
      detectedCodes: []
    )
    XCTAssertFalse(renderer.canRender(message))
  }

  func testCanRender_withNilCodes_returnsFalse() {
    let message = Message(
      id: 1, guid: "g1", text: "No codes", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1"
    )
    XCTAssertFalse(renderer.canRender(message))
  }

  func testCanRender_withMultipleCodes_returnsTrue() {
    let message = Message(
      id: 1, guid: "g1", text: "Codes: 1234 and 5678", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      attachments: [],
      detectedCodes: [DetectedCode(value: "1234"), DetectedCode(value: "5678")]
    )
    XCTAssertTrue(renderer.canRender(message))
  }
}
