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

  func testCanRender_withLinkPreview_returnsTrue() {
    let preview = LinkPreview(url: "https://apple.com", title: "Apple")
    let message = makeMessage("https://apple.com", linkPreview: preview)
    XCTAssertTrue(renderer.canRender(message))
  }

  func testCanRender_withoutLinkPreview_returnsFalse() {
    let message = makeMessage("Check https://apple.com", linkPreview: nil)
    XCTAssertFalse(renderer.canRender(message))
  }

  func testCanRender_nilText_withLinkPreview_returnsTrue() {
    let preview = LinkPreview(url: "https://apple.com", title: "Apple")
    let message = makeMessage(nil, linkPreview: preview)
    XCTAssertTrue(renderer.canRender(message))
  }

  func testCanRender_noLinkPreview_noURL_returnsFalse() {
    let message = makeMessage("No links here", linkPreview: nil)
    XCTAssertFalse(renderer.canRender(message))
  }

  private func makeMessage(_ text: String?, linkPreview: LinkPreview? = nil) -> Message {
    Message(
      id: 1, guid: "g1", text: text, date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1", linkPreview: linkPreview)
  }
}
