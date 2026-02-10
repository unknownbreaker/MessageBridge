import XCTest

@testable import MessageBridgeCore

final class HandleTests: XCTestCase {

  // MARK: - displayAddress Tests

  func testDisplayAddress_withPhoneNumber_returnsPhoneNumber() {
    let handle = Handle(id: 1, address: "+15551234567", service: "iMessage")

    XCTAssertEqual(handle.displayAddress, "+15551234567")
  }

  func testDisplayAddress_withEmail_returnsEmail() {
    let handle = Handle(id: 1, address: "john@example.com", service: "iMessage")

    XCTAssertEqual(handle.displayAddress, "john@example.com")
  }

  func testDisplayAddress_withFormattedNumber_returnsFormattedNumber() {
    let handle = Handle(id: 1, address: "555-123-4567", service: "SMS")

    XCTAssertEqual(handle.displayAddress, "555-123-4567")
  }

  // MARK: - Initialization Tests

  func testInit_setsAllProperties() {
    let handle = Handle(id: 42, address: "+15559876543", service: "SMS")

    XCTAssertEqual(handle.id, 42)
    XCTAssertEqual(handle.address, "+15559876543")
    XCTAssertEqual(handle.service, "SMS")
    XCTAssertNil(handle.contactName)
  }

  func testInit_withContactName_setsAllProperties() {
    let handle = Handle(id: 42, address: "+15559876543", service: "SMS", contactName: "John Doe")

    XCTAssertEqual(handle.id, 42)
    XCTAssertEqual(handle.address, "+15559876543")
    XCTAssertEqual(handle.service, "SMS")
    XCTAssertEqual(handle.contactName, "John Doe")
  }

  // MARK: - displayName Tests

  func testDisplayName_withContactName_returnsContactName() {
    let handle = Handle(
      id: 1, address: "+15551234567", service: "iMessage", contactName: "Jane Smith")

    XCTAssertEqual(handle.displayName, "Jane Smith")
  }

  func testDisplayName_withoutContactName_returnsAddress() {
    let handle = Handle(id: 1, address: "+15551234567", service: "iMessage")

    XCTAssertEqual(handle.displayName, "+15551234567")
  }

  func testDisplayName_withNilContactName_returnsAddress() {
    let handle = Handle(id: 1, address: "user@example.com", service: "iMessage", contactName: nil)

    XCTAssertEqual(handle.displayName, "user@example.com")
  }

  // MARK: - Codable Tests

  func testCodable_encodesAndDecodes() throws {
    let original = Handle(id: 1, address: "+15551234567", service: "iMessage")

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Handle.self, from: data)

    XCTAssertEqual(decoded.id, original.id)
    XCTAssertEqual(decoded.address, original.address)
    XCTAssertEqual(decoded.service, original.service)
    XCTAssertNil(decoded.contactName)
  }

  func testCodable_withContactName_encodesAndDecodes() throws {
    let original = Handle(
      id: 1, address: "+15551234567", service: "iMessage", contactName: "Test User")

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Handle.self, from: data)

    XCTAssertEqual(decoded.id, original.id)
    XCTAssertEqual(decoded.address, original.address)
    XCTAssertEqual(decoded.service, original.service)
    XCTAssertEqual(decoded.contactName, "Test User")
  }
}
