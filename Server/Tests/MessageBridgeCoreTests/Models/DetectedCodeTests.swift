import XCTest

@testable import MessageBridgeCore

final class DetectedCodeTests: XCTestCase {

  // MARK: - Initialization Tests

  func testInit_setsAllProperties() {
    let code = DetectedCode(value: "123456", confidence: .high)

    XCTAssertEqual(code.value, "123456")
    XCTAssertEqual(code.confidence, .high)
  }

  func testInit_withMediumConfidence_setsConfidence() {
    let code = DetectedCode(value: "ABCD1234", confidence: .medium)

    XCTAssertEqual(code.value, "ABCD1234")
    XCTAssertEqual(code.confidence, .medium)
  }

  // MARK: - Equatable Tests

  func testEquatable_equalValues_returnsTrue() {
    let code1 = DetectedCode(value: "123456", confidence: .high)
    let code2 = DetectedCode(value: "123456", confidence: .high)

    XCTAssertEqual(code1, code2)
  }

  func testEquatable_differentValues_returnsFalse() {
    let code1 = DetectedCode(value: "123456", confidence: .high)
    let code2 = DetectedCode(value: "654321", confidence: .high)

    XCTAssertNotEqual(code1, code2)
  }

  func testEquatable_differentConfidence_returnsFalse() {
    let code1 = DetectedCode(value: "123456", confidence: .high)
    let code2 = DetectedCode(value: "123456", confidence: .medium)

    XCTAssertNotEqual(code1, code2)
  }

  // MARK: - Codable Tests

  func testCodable_encodesAndDecodes() throws {
    let original = DetectedCode(value: "G-582941", confidence: .high)

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(DetectedCode.self, from: data)

    XCTAssertEqual(decoded.value, original.value)
    XCTAssertEqual(decoded.confidence, original.confidence)
  }

  func testCodable_withMediumConfidence_encodesAndDecodes() throws {
    let original = DetectedCode(value: "847293", confidence: .medium)

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(DetectedCode.self, from: data)

    XCTAssertEqual(decoded, original)
  }

  // MARK: - Confidence Enum Tests

  func testConfidence_highRawValue() {
    XCTAssertEqual(DetectedCode.Confidence.high.rawValue, "high")
  }

  func testConfidence_mediumRawValue() {
    XCTAssertEqual(DetectedCode.Confidence.medium.rawValue, "medium")
  }

  func testConfidence_decodesFromRawValue() {
    let high = DetectedCode.Confidence(rawValue: "high")
    let medium = DetectedCode.Confidence(rawValue: "medium")

    XCTAssertEqual(high, .high)
    XCTAssertEqual(medium, .medium)
  }
}
