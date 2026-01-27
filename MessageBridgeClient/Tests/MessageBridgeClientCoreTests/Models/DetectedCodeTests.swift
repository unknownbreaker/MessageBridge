import XCTest

@testable import MessageBridgeClientCore

final class DetectedCodeTests: XCTestCase {
  func testInit_storesValue() {
    let code = DetectedCode(value: "847293")
    XCTAssertEqual(code.value, "847293")
  }

  func testEquatable_sameValues_areEqual() {
    let a = DetectedCode(value: "1234")
    let b = DetectedCode(value: "1234")
    XCTAssertEqual(a, b)
  }

  func testEquatable_differentValues_areNotEqual() {
    let a = DetectedCode(value: "1234")
    let b = DetectedCode(value: "5678")
    XCTAssertNotEqual(a, b)
  }

  func testCodable_roundTrips() throws {
    let code = DetectedCode(value: "G-582941")
    let data = try JSONEncoder().encode(code)
    let decoded = try JSONDecoder().decode(DetectedCode.self, from: data)
    XCTAssertEqual(decoded, code)
  }
}
