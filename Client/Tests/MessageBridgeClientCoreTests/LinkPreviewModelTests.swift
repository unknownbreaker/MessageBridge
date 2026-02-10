import XCTest

@testable import MessageBridgeClientCore

final class LinkPreviewModelTests: XCTestCase {

  func testLinkPreview_decodesFromJSON() throws {
    let json = """
      {
        "url": "https://apple.com",
        "title": "Apple",
        "summary": "Innovation at its finest.",
        "siteName": "Apple",
        "imageBase64": "base64data"
      }
      """
    let decoded = try JSONDecoder().decode(LinkPreview.self, from: json.data(using: .utf8)!)

    XCTAssertEqual(decoded.url, "https://apple.com")
    XCTAssertEqual(decoded.title, "Apple")
    XCTAssertEqual(decoded.summary, "Innovation at its finest.")
    XCTAssertEqual(decoded.siteName, "Apple")
    XCTAssertEqual(decoded.imageBase64, "base64data")
  }

  func testLinkPreview_decodesWithNilOptionals() throws {
    let json = """
      {"url": "https://example.com"}
      """
    let decoded = try JSONDecoder().decode(LinkPreview.self, from: json.data(using: .utf8)!)

    XCTAssertEqual(decoded.url, "https://example.com")
    XCTAssertNil(decoded.title)
    XCTAssertNil(decoded.summary)
  }

  func testMessage_decodesLinkPreview() throws {
    let json = """
      {
        "id": 1,
        "guid": "g1",
        "text": "https://apple.com",
        "date": 0,
        "isFromMe": true,
        "conversationId": "c1",
        "linkPreview": {
          "url": "https://apple.com",
          "title": "Apple"
        }
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)

    XCTAssertNotNil(message.linkPreview)
    XCTAssertEqual(message.linkPreview?.url, "https://apple.com")
    XCTAssertEqual(message.linkPreview?.title, "Apple")
  }

  func testMessage_decodesWithoutLinkPreview() throws {
    let json = """
      {
        "id": 1,
        "guid": "g1",
        "text": "Hello",
        "date": 0,
        "isFromMe": true,
        "conversationId": "c1"
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)

    XCTAssertNil(message.linkPreview)
  }

  func testLinkPreview_domain_extractsHost() {
    let preview = LinkPreview(url: "https://www.apple.com/iphone/compare/", title: nil)
    XCTAssertEqual(preview.domain, "apple.com")
  }

  func testLinkPreview_domain_handlesNoDomain() {
    let preview = LinkPreview(url: "not-a-url", title: nil)
    XCTAssertEqual(preview.domain, "not-a-url")
  }
}
