import XCTest

@testable import MessageBridgeCore

final class AttachmentMetadataTests: XCTestCase {

  // MARK: - Initialization Tests

  func testInit_withAllParameters_setsProperties() {
    let metadata = AttachmentMetadata(
      width: 1920,
      height: 1080,
      duration: 120.5,
      thumbnailPath: "/path/to/thumb.jpg"
    )

    XCTAssertEqual(metadata.width, 1920)
    XCTAssertEqual(metadata.height, 1080)
    XCTAssertEqual(metadata.duration, 120.5)
    XCTAssertEqual(metadata.thumbnailPath, "/path/to/thumb.jpg")
  }

  func testInit_withDefaults_setsNilValues() {
    let metadata = AttachmentMetadata()

    XCTAssertNil(metadata.width)
    XCTAssertNil(metadata.height)
    XCTAssertNil(metadata.duration)
    XCTAssertNil(metadata.thumbnailPath)
  }

  func testInit_withPartialParameters_setsOnlyProvided() {
    let metadata = AttachmentMetadata(width: 640, height: 480)

    XCTAssertEqual(metadata.width, 640)
    XCTAssertEqual(metadata.height, 480)
    XCTAssertNil(metadata.duration)
    XCTAssertNil(metadata.thumbnailPath)
  }

  func testInit_withDurationOnly_setsDuration() {
    let metadata = AttachmentMetadata(duration: 180.0)

    XCTAssertNil(metadata.width)
    XCTAssertNil(metadata.height)
    XCTAssertEqual(metadata.duration, 180.0)
    XCTAssertNil(metadata.thumbnailPath)
  }

  // MARK: - Equatable Tests

  func testEquatable_withSameValues_returnsTrue() {
    let metadata1 = AttachmentMetadata(width: 100, height: 200)
    let metadata2 = AttachmentMetadata(width: 100, height: 200)

    XCTAssertEqual(metadata1, metadata2)
  }

  func testEquatable_withDifferentWidth_returnsFalse() {
    let metadata1 = AttachmentMetadata(width: 100, height: 200)
    let metadata2 = AttachmentMetadata(width: 200, height: 200)

    XCTAssertNotEqual(metadata1, metadata2)
  }

  func testEquatable_withDifferentHeight_returnsFalse() {
    let metadata1 = AttachmentMetadata(width: 100, height: 200)
    let metadata2 = AttachmentMetadata(width: 100, height: 300)

    XCTAssertNotEqual(metadata1, metadata2)
  }

  func testEquatable_withAllNilValues_returnsTrue() {
    let metadata1 = AttachmentMetadata()
    let metadata2 = AttachmentMetadata()

    XCTAssertEqual(metadata1, metadata2)
  }

  func testEquatable_withAllValuesSet_returnsTrue() {
    let metadata1 = AttachmentMetadata(
      width: 1920, height: 1080, duration: 60.0, thumbnailPath: "/thumb.jpg")
    let metadata2 = AttachmentMetadata(
      width: 1920, height: 1080, duration: 60.0, thumbnailPath: "/thumb.jpg")

    XCTAssertEqual(metadata1, metadata2)
  }

  // MARK: - Codable Tests

  func testCodable_roundTrip_preservesValues() throws {
    let original = AttachmentMetadata(width: 640, height: 480, duration: 30.0)
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AttachmentMetadata.self, from: encoded)

    XCTAssertEqual(decoded, original)
  }

  func testCodable_withAllNilValues_roundTrips() throws {
    let original = AttachmentMetadata()
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AttachmentMetadata.self, from: encoded)

    XCTAssertEqual(decoded, original)
  }

  func testCodable_withAllValues_roundTrips() throws {
    let original = AttachmentMetadata(
      width: 3840,
      height: 2160,
      duration: 7200.5,
      thumbnailPath: "/var/cache/thumbnails/abc123.jpg"
    )
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AttachmentMetadata.self, from: encoded)

    XCTAssertEqual(decoded, original)
  }

  func testCodable_encodesToExpectedJSON() throws {
    let metadata = AttachmentMetadata(width: 800, height: 600)
    let encoded = try JSONEncoder().encode(metadata)
    let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

    XCTAssertEqual(json?["width"] as? Int, 800)
    XCTAssertEqual(json?["height"] as? Int, 600)
    XCTAssertNil(json?["duration"])
    XCTAssertNil(json?["thumbnailPath"])
  }
}
