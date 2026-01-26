import XCTest

@testable import MessageBridgeCore

final class TextHighlightTests: XCTestCase {

  // MARK: - Initialization Tests

  func testInit_setsAllProperties() {
    let highlight = TextHighlight(text: "123456", startIndex: 10, endIndex: 16, type: .code)

    XCTAssertEqual(highlight.text, "123456")
    XCTAssertEqual(highlight.startIndex, 10)
    XCTAssertEqual(highlight.endIndex, 16)
    XCTAssertEqual(highlight.type, .code)
  }

  func testInit_withPhoneNumber_setsType() {
    let highlight = TextHighlight(
      text: "+15551234567", startIndex: 0, endIndex: 12, type: .phoneNumber)

    XCTAssertEqual(highlight.text, "+15551234567")
    XCTAssertEqual(highlight.type, .phoneNumber)
  }

  func testInit_withMention_setsType() {
    let highlight = TextHighlight(text: "@john", startIndex: 5, endIndex: 10, type: .mention)

    XCTAssertEqual(highlight.text, "@john")
    XCTAssertEqual(highlight.type, .mention)
  }

  // MARK: - Equatable Tests

  func testEquatable_equalValues_returnsTrue() {
    let highlight1 = TextHighlight(text: "123456", startIndex: 10, endIndex: 16, type: .code)
    let highlight2 = TextHighlight(text: "123456", startIndex: 10, endIndex: 16, type: .code)

    XCTAssertEqual(highlight1, highlight2)
  }

  func testEquatable_differentText_returnsFalse() {
    let highlight1 = TextHighlight(text: "123456", startIndex: 10, endIndex: 16, type: .code)
    let highlight2 = TextHighlight(text: "654321", startIndex: 10, endIndex: 16, type: .code)

    XCTAssertNotEqual(highlight1, highlight2)
  }

  func testEquatable_differentStartIndex_returnsFalse() {
    let highlight1 = TextHighlight(text: "123456", startIndex: 10, endIndex: 16, type: .code)
    let highlight2 = TextHighlight(text: "123456", startIndex: 5, endIndex: 16, type: .code)

    XCTAssertNotEqual(highlight1, highlight2)
  }

  func testEquatable_differentEndIndex_returnsFalse() {
    let highlight1 = TextHighlight(text: "123456", startIndex: 10, endIndex: 16, type: .code)
    let highlight2 = TextHighlight(text: "123456", startIndex: 10, endIndex: 20, type: .code)

    XCTAssertNotEqual(highlight1, highlight2)
  }

  func testEquatable_differentType_returnsFalse() {
    let highlight1 = TextHighlight(text: "123456", startIndex: 10, endIndex: 16, type: .code)
    let highlight2 = TextHighlight(text: "123456", startIndex: 10, endIndex: 16, type: .phoneNumber)

    XCTAssertNotEqual(highlight1, highlight2)
  }

  // MARK: - Codable Tests

  func testCodable_encodesAndDecodes() throws {
    let original = TextHighlight(text: "G-582941", startIndex: 0, endIndex: 8, type: .code)

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(TextHighlight.self, from: data)

    XCTAssertEqual(decoded.text, original.text)
    XCTAssertEqual(decoded.startIndex, original.startIndex)
    XCTAssertEqual(decoded.endIndex, original.endIndex)
    XCTAssertEqual(decoded.type, original.type)
  }

  func testCodable_withPhoneNumber_encodesAndDecodes() throws {
    let original = TextHighlight(
      text: "+15551234567", startIndex: 20, endIndex: 32, type: .phoneNumber)

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(TextHighlight.self, from: data)

    XCTAssertEqual(decoded, original)
  }

  func testCodable_withMention_encodesAndDecodes() throws {
    let original = TextHighlight(text: "@jane", startIndex: 0, endIndex: 5, type: .mention)

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(TextHighlight.self, from: data)

    XCTAssertEqual(decoded, original)
  }

  // MARK: - HighlightType Enum Tests

  func testHighlightType_codeRawValue() {
    XCTAssertEqual(TextHighlight.HighlightType.code.rawValue, "code")
  }

  func testHighlightType_phoneNumberRawValue() {
    XCTAssertEqual(TextHighlight.HighlightType.phoneNumber.rawValue, "phoneNumber")
  }

  func testHighlightType_mentionRawValue() {
    XCTAssertEqual(TextHighlight.HighlightType.mention.rawValue, "mention")
  }

  func testHighlightType_decodesFromRawValue() {
    let code = TextHighlight.HighlightType(rawValue: "code")
    let phoneNumber = TextHighlight.HighlightType(rawValue: "phoneNumber")
    let mention = TextHighlight.HighlightType(rawValue: "mention")

    XCTAssertEqual(code, .code)
    XCTAssertEqual(phoneNumber, .phoneNumber)
    XCTAssertEqual(mention, .mention)
  }
}
