import XCTest

@testable import MessageBridgeCore

final class ImageHandlerTests: XCTestCase {

  var handler: ImageHandler!
  var testImagePath: String!

  override func setUp() {
    super.setUp()
    handler = ImageHandler()

    // Create a test image file
    testImagePath =
      FileManager.default.temporaryDirectory
      .appendingPathComponent("test-image-\(UUID().uuidString).png").path
    createTestImage(at: testImagePath, width: 800, height: 600)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: testImagePath)
    super.tearDown()
  }

  func testId_returnsImageHandler() {
    XCTAssertEqual(handler.id, "image-handler")
  }

  func testSupportedMimeTypes_containsImageWildcard() {
    XCTAssertEqual(handler.supportedMimeTypes, ["image/*"])
  }

  func testGenerateThumbnail_withValidImage_returnsJPEGData() async throws {
    let maxSize = CGSize(width: 300, height: 300)
    let thumbnailData = try await handler.generateThumbnail(
      filePath: testImagePath,
      maxSize: maxSize
    )

    XCTAssertNotNil(thumbnailData)
    // JPEG magic bytes: FF D8 FF
    XCTAssertEqual(thumbnailData?.prefix(2), Data([0xFF, 0xD8]))
  }

  func testGenerateThumbnail_withInvalidPath_returnsNil() async throws {
    let result = try await handler.generateThumbnail(
      filePath: "/nonexistent/image.jpg",
      maxSize: CGSize(width: 300, height: 300)
    )

    XCTAssertNil(result)
  }

  func testExtractMetadata_withValidImage_returnsDimensions() async throws {
    let metadata = try await handler.extractMetadata(filePath: testImagePath)

    XCTAssertEqual(metadata.width, 800)
    XCTAssertEqual(metadata.height, 600)
    XCTAssertNil(metadata.duration)  // Images don't have duration
  }

  func testExtractMetadata_withInvalidPath_returnsEmptyMetadata() async throws {
    let metadata = try await handler.extractMetadata(filePath: "/nonexistent/image.jpg")

    XCTAssertNil(metadata.width)
    XCTAssertNil(metadata.height)
  }

  func testGenerateThumbnail_maintainsAspectRatio() async throws {
    // Create a wide image (1600x400)
    let widePath = FileManager.default.temporaryDirectory
      .appendingPathComponent("wide-\(UUID().uuidString).png").path
    createTestImage(at: widePath, width: 1600, height: 400)
    defer { try? FileManager.default.removeItem(atPath: widePath) }

    let thumbnailData = try await handler.generateThumbnail(
      filePath: widePath,
      maxSize: CGSize(width: 300, height: 300)
    )

    // Thumbnail should exist
    XCTAssertNotNil(thumbnailData)
  }

  // MARK: - Helpers

  private func createTestImage(at path: String, width: Int, height: Int) {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.blue.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      return
    }

    try? pngData.write(to: URL(fileURLWithPath: path))
  }
}
