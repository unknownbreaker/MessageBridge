import XCTest

@testable import MessageBridgeClientCore

final class TextHighlightTests: XCTestCase {
  func testInit_storesProperties() {
    let highlight = TextHighlight(text: "847293", type: .code)
    XCTAssertEqual(highlight.text, "847293")
    XCTAssertEqual(highlight.type, .code)
  }

  func testEquatable_sameValues_areEqual() {
    let a = TextHighlight(text: "test", type: .link)
    let b = TextHighlight(text: "test", type: .link)
    XCTAssertEqual(a, b)
  }

  func testAllHighlightTypes_exist() {
    _ = TextHighlight.HighlightType.code
    _ = TextHighlight.HighlightType.link
    _ = TextHighlight.HighlightType.phoneNumber
    _ = TextHighlight.HighlightType.email
  }

  func testCodable_roundTrips() throws {
    let highlight = TextHighlight(text: "https://example.com", type: .link)
    let data = try JSONEncoder().encode(highlight)
    let decoded = try JSONDecoder().decode(TextHighlight.self, from: data)
    XCTAssertEqual(decoded, highlight)
  }
}
