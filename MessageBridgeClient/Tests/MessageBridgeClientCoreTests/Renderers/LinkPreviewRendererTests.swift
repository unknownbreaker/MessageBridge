import XCTest

@testable import MessageBridgeClientCore

final class LinkPreviewRendererTests: XCTestCase {
  let renderer = LinkPreviewRenderer()

  func testId_isLinkPreview() {
    XCTAssertEqual(renderer.id, "link-preview")
  }

  func testPriority_is100() {
    XCTAssertEqual(renderer.priority, 100)
  }

  func testCanRender_withURL_returnsTrue() {
    XCTAssertTrue(renderer.canRender(makeMessage("Check https://apple.com")))
  }

  func testCanRender_withoutURL_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage("No links here")))
  }

  func testCanRender_nilText_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage(nil)))
  }

  func testCanRender_emptyText_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage("")))
  }

  private func makeMessage(_ text: String?) -> Message {
    Message(
      id: 1, guid: "g1", text: text, date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
  }
}
