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
    }
}
