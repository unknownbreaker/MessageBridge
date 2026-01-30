import XCTest

@testable import MessageBridgeCore

final class LinkPreviewTests: XCTestCase {

  func testLinkPreview_encodesAndDecodes() throws {
    let preview = LinkPreview(
      url: "https://apple.com",
      title: "Apple",
      summary: "Apple leads the world in innovation.",
      siteName: "Apple",
      imageBase64: "base64data"
    )

    let data = try JSONEncoder().encode(preview)
    let decoded = try JSONDecoder().decode(LinkPreview.self, from: data)

    XCTAssertEqual(decoded.url, "https://apple.com")
    XCTAssertEqual(decoded.title, "Apple")
    XCTAssertEqual(decoded.summary, "Apple leads the world in innovation.")
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
    XCTAssertNil(decoded.siteName)
    XCTAssertNil(decoded.imageBase64)
  }

  func testMessage_withLinkPreview_encodesAndDecodes() throws {
    let preview = LinkPreview(
      url: "https://apple.com",
      title: "Apple",
      summary: nil,
      siteName: "Apple",
      imageBase64: nil
    )

    let message = Message(
      id: 1, guid: "g1", text: "https://apple.com",
      date: Date(timeIntervalSinceReferenceDate: 0),
      isFromMe: true, handleId: nil,
      conversationId: "c1",
      linkPreview: preview
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = try encoder.encode(message)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(Message.self, from: data)

    XCTAssertEqual(decoded.linkPreview?.url, "https://apple.com")
    XCTAssertEqual(decoded.linkPreview?.title, "Apple")
    XCTAssertEqual(decoded.linkPreview?.siteName, "Apple")
  }

  func testMessage_withoutLinkPreview_decodesNil() throws {
    let message = Message(
      id: 1, guid: "g1", text: "Hello",
      date: Date(timeIntervalSinceReferenceDate: 0),
      isFromMe: true, handleId: nil,
      conversationId: "c1"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = try encoder.encode(message)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(Message.self, from: data)

    XCTAssertNil(decoded.linkPreview)
  }
}
