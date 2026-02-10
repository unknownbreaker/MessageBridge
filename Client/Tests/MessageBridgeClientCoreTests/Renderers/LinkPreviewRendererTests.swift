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

  func testStripURL_textURLHasExtraQueryParams_stripsIt() {
    // Preview URL from plist has no query params, but text URL does (e.g. Instagram ?igsh=...)
    let result = LinkPreviewRenderer.stripURL(
      "https://www.instagram.com/p/ABC123/",
      from: "https://www.instagram.com/p/ABC123/?igsh=abc123def456")
    XCTAssertNil(result)
  }

  func testStripURL_textURLHasDifferentQueryParams_stripsIt() {
    // Preview URL has one set of query params, text URL has different ones
    let result = LinkPreviewRenderer.stripURL(
      "https://example.com/page?ref=share",
      from: "Check this https://example.com/page?utm_source=twitter&utm_medium=social end")
    XCTAssertEqual(result, "Check this end")
  }

  func testStripURL_plistURLCompletelyDifferentHost_stillStripsTextURL() {
    // Real case: youtu.be in text → youtube.com in plist (redirect)
    // Since we know a link preview exists, strip the URL in the text regardless
    let result = LinkPreviewRenderer.stripURL(
      "https://www.youtube.com/watch?v=Iqv-z5R3phI",
      from: "https://youtu.be/Iqv-z5R3phI")
    XCTAssertNil(result)
  }

  func testStripURL_instagramUsernameInPlistPath_stillStripsTextURL() {
    // Real case: Instagram adds username to the canonical URL path
    // Text: /p/ABC123/?igsh=...  Plist: /fox4news/p/ABC123/
    let result = LinkPreviewRenderer.stripURL(
      "https://www.instagram.com/fox4news/p/DUHNfhKDHg0/",
      from: "https://www.instagram.com/p/DUHNfhKDHg0/?igsh=MWcxeTFycGhhamZ5Mg==")
    XCTAssertNil(result)
  }

  func testStripURL_textWithURLAndSurroundingText_preservesText() {
    // Strip the URL but keep the non-URL text
    let result = LinkPreviewRenderer.stripURL(
      "https://www.youtube.com/watch?v=abc",
      from: "Watch this https://youtu.be/abc great video")
    XCTAssertEqual(result, "Watch this great video")
  }

  func testStripURL_noURLInText_returnsText() {
    // Text has no URL at all — nothing to strip
    let result = LinkPreviewRenderer.stripURL(
      "https://apple.com/iphone",
      from: "Just some plain text")
    XCTAssertEqual(result, "Just some plain text")
  }

  private func makeMessage(_ text: String?, linkPreview: LinkPreview? = nil) -> Message {
    Message(
      id: 1, guid: "g1", text: text, date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1", linkPreview: linkPreview)
  }
}
