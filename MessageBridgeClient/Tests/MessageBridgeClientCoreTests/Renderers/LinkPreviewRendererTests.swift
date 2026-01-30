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

  // MARK: - URL Stripping

  func testStripURL_textIsOnlyURL_returnsNil() {
    let result = LinkPreviewRenderer.stripURL("https://apple.com", from: "https://apple.com")
    XCTAssertNil(result)
  }

  func testStripURL_textHasURLAndWords_returnsWordsOnly() {
    let result = LinkPreviewRenderer.stripURL(
      "https://apple.com", from: "Check this out https://apple.com")
    XCTAssertEqual(result, "Check this out")
  }

  func testStripURL_textIsNil_returnsNil() {
    let result = LinkPreviewRenderer.stripURL("https://apple.com", from: nil)
    XCTAssertNil(result)
  }

  func testStripURL_urlNotInText_returnsFullText() {
    let result = LinkPreviewRenderer.stripURL(
      "https://apple.com", from: "Check this out")
    XCTAssertEqual(result, "Check this out")
  }

  func testStripURL_urlWithSurroundingWhitespace_trimmed() {
    let result = LinkPreviewRenderer.stripURL(
      "https://apple.com", from: "  https://apple.com  ")
    XCTAssertNil(result)
  }

  private func makeMessage(_ text: String?, linkPreview: LinkPreview? = nil) -> Message {
    Message(
      id: 1, guid: "g1", text: text, date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1", linkPreview: linkPreview)
  }
}
