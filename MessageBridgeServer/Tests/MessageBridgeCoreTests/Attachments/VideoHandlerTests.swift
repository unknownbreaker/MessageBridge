import AVFoundation
import XCTest

@testable import MessageBridgeCore

final class VideoHandlerTests: XCTestCase {

  var handler: VideoHandler!

  override func setUp() {
    super.setUp()
    handler = VideoHandler()
  }

  func testId_returnsVideoHandler() {
    XCTAssertEqual(handler.id, "video-handler")
  }

  func testSupportedMimeTypes_containsVideoWildcard() {
    XCTAssertEqual(handler.supportedMimeTypes, ["video/*"])
  }

  func testGenerateThumbnail_withInvalidPath_returnsNil() async throws {
    let result = try await handler.generateThumbnail(
      filePath: "/nonexistent/video.mp4",
      maxSize: CGSize(width: 300, height: 300)
    )

    XCTAssertNil(result)
  }

  func testExtractMetadata_withInvalidPath_returnsEmptyMetadata() async throws {
    let metadata = try await handler.extractMetadata(filePath: "/nonexistent/video.mp4")

    XCTAssertNil(metadata.width)
    XCTAssertNil(metadata.height)
    XCTAssertNil(metadata.duration)
  }

  func testGenerateThumbnail_withNonVideoFile_returnsNil() async throws {
    // Create a text file (not a video)
    let textPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("not-a-video-\(UUID().uuidString).mp4").path
    try "This is not a video".write(toFile: textPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: textPath) }

    let result = try await handler.generateThumbnail(
      filePath: textPath,
      maxSize: CGSize(width: 300, height: 300)
    )

    XCTAssertNil(result)
  }
}
