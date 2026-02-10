import XCTest

@testable import MessageBridgeCore

final class MentionTests: XCTestCase {

  // MARK: - Initialization Tests

  func testInit_setsAllProperties() {
    let mention = Mention(text: "@john", handle: "+15551234567")

    XCTAssertEqual(mention.text, "@john")
    XCTAssertEqual(mention.handle, "+15551234567")
  }

  func testInit_withNilHandle_setsTextOnly() {
    let mention = Mention(text: "@jane")

    XCTAssertEqual(mention.text, "@jane")
    XCTAssertNil(mention.handle)
  }

  func testInit_withEmail_setsHandle() {
    let mention = Mention(text: "@john", handle: "john@example.com")

    XCTAssertEqual(mention.text, "@john")
    XCTAssertEqual(mention.handle, "john@example.com")
  }

  // MARK: - Equatable Tests

  func testEquatable_equalValues_returnsTrue() {
    let mention1 = Mention(text: "@john", handle: "+15551234567")
    let mention2 = Mention(text: "@john", handle: "+15551234567")

    XCTAssertEqual(mention1, mention2)
  }

  func testEquatable_bothNilHandles_returnsTrue() {
    let mention1 = Mention(text: "@john")
    let mention2 = Mention(text: "@john")

    XCTAssertEqual(mention1, mention2)
  }

  func testEquatable_differentText_returnsFalse() {
    let mention1 = Mention(text: "@john", handle: "+15551234567")
    let mention2 = Mention(text: "@jane", handle: "+15551234567")

    XCTAssertNotEqual(mention1, mention2)
  }

  func testEquatable_differentHandle_returnsFalse() {
    let mention1 = Mention(text: "@john", handle: "+15551234567")
    let mention2 = Mention(text: "@john", handle: "+15559876543")

    XCTAssertNotEqual(mention1, mention2)
  }

  func testEquatable_nilVsNonNilHandle_returnsFalse() {
    let mention1 = Mention(text: "@john")
    let mention2 = Mention(text: "@john", handle: "+15551234567")

    XCTAssertNotEqual(mention1, mention2)
  }

  // MARK: - Codable Tests

  func testCodable_encodesAndDecodes() throws {
    let original = Mention(text: "@john", handle: "+15551234567")

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Mention.self, from: data)

    XCTAssertEqual(decoded.text, original.text)
    XCTAssertEqual(decoded.handle, original.handle)
  }

  func testCodable_withNilHandle_encodesAndDecodes() throws {
    let original = Mention(text: "@jane")

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Mention.self, from: data)

    XCTAssertEqual(decoded.text, original.text)
    XCTAssertNil(decoded.handle)
  }

  func testCodable_withEmailHandle_encodesAndDecodes() throws {
    let original = Mention(text: "@bob", handle: "bob@example.com")

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Mention.self, from: data)

    XCTAssertEqual(decoded, original)
  }
}
