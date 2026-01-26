import XCTest

@testable import MessageBridgeCore

final class AttachmentHandlerTests: XCTestCase {

  // MARK: - Protocol Requirements Tests

  func testProtocol_hasRequiredIdProperty() {
    let handler: any AttachmentHandler = MockAttachmentHandler(
      id: "test-handler",
      supportedMimeTypes: ["image/*", "video/mp4"]
    )

    XCTAssertEqual(handler.id, "test-handler")
  }

  func testProtocol_hasRequiredSupportedMimeTypesProperty() {
    let handler = MockAttachmentHandler(
      id: "test-handler",
      supportedMimeTypes: ["image/*", "video/mp4"]
    )

    XCTAssertEqual(handler.supportedMimeTypes, ["image/*", "video/mp4"])
  }

  func testProtocol_supportsMimeTypeWildcards() {
    let handler = MockAttachmentHandler(
      id: "image-handler",
      supportedMimeTypes: ["image/*"]
    )

    XCTAssertTrue(handler.supportedMimeTypes.contains("image/*"))
  }

  func testProtocol_supportsSpecificMimeTypes() {
    let handler = MockAttachmentHandler(
      id: "video-handler",
      supportedMimeTypes: ["video/mp4", "video/quicktime", "video/x-m4v"]
    )

    XCTAssertEqual(handler.supportedMimeTypes.count, 3)
    XCTAssertTrue(handler.supportedMimeTypes.contains("video/mp4"))
    XCTAssertTrue(handler.supportedMimeTypes.contains("video/quicktime"))
  }

  // MARK: - generateThumbnail Tests

  func testGenerateThumbnail_returnsThumbnailData() async throws {
    let expectedData = Data([0x00, 0x01, 0x02, 0x03])
    let handler = MockAttachmentHandler(thumbnailResult: expectedData)

    let result = try await handler.generateThumbnail(
      filePath: "/fake/path/image.jpg",
      maxSize: CGSize(width: 300, height: 300)
    )

    XCTAssertEqual(result, expectedData)
  }

  func testGenerateThumbnail_canReturnNil() async throws {
    let handler = MockAttachmentHandler(thumbnailResult: nil)

    let result = try await handler.generateThumbnail(
      filePath: "/fake/path/document.pdf",
      maxSize: CGSize(width: 300, height: 300)
    )

    XCTAssertNil(result)
  }

  func testGenerateThumbnail_receivesCorrectParameters() async throws {
    let handler = MockAttachmentHandler()

    _ = try await handler.generateThumbnail(
      filePath: "/test/path.jpg",
      maxSize: CGSize(width: 150, height: 200)
    )

    XCTAssertEqual(handler.lastThumbnailFilePath, "/test/path.jpg")
    XCTAssertEqual(handler.lastThumbnailMaxSize, CGSize(width: 150, height: 200))
  }

  func testGenerateThumbnail_canThrowError() async {
    let handler = MockAttachmentHandler()
    handler.shouldThrowOnThumbnail = true

    do {
      _ = try await handler.generateThumbnail(
        filePath: "/fake/path.jpg",
        maxSize: CGSize(width: 300, height: 300)
      )
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertTrue(error is MockAttachmentHandlerError)
    }
  }

  // MARK: - extractMetadata Tests

  func testExtractMetadata_returnsMetadata() async throws {
    let expectedMetadata = AttachmentMetadata(width: 1920, height: 1080)
    let handler = MockAttachmentHandler(metadataResult: expectedMetadata)

    let result = try await handler.extractMetadata(filePath: "/fake/video.mp4")

    XCTAssertEqual(result, expectedMetadata)
    XCTAssertEqual(result.width, 1920)
    XCTAssertEqual(result.height, 1080)
  }

  func testExtractMetadata_returnsMetadataWithDuration() async throws {
    let expectedMetadata = AttachmentMetadata(width: 1280, height: 720, duration: 125.5)
    let handler = MockAttachmentHandler(metadataResult: expectedMetadata)

    let result = try await handler.extractMetadata(filePath: "/fake/video.mp4")

    XCTAssertEqual(result.duration, 125.5)
  }

  func testExtractMetadata_receivesCorrectFilePath() async throws {
    let handler = MockAttachmentHandler()

    _ = try await handler.extractMetadata(filePath: "/test/document.pdf")

    XCTAssertEqual(handler.lastMetadataFilePath, "/test/document.pdf")
  }

  func testExtractMetadata_canThrowError() async {
    let handler = MockAttachmentHandler()
    handler.shouldThrowOnMetadata = true

    do {
      _ = try await handler.extractMetadata(filePath: "/fake/file.txt")
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertTrue(error is MockAttachmentHandlerError)
    }
  }

  func testExtractMetadata_returnsEmptyMetadataWhenNoDimensions() async throws {
    let emptyMetadata = AttachmentMetadata()
    let handler = MockAttachmentHandler(metadataResult: emptyMetadata)

    let result = try await handler.extractMetadata(filePath: "/fake/unknown.bin")

    XCTAssertNil(result.width)
    XCTAssertNil(result.height)
    XCTAssertNil(result.duration)
  }

  // MARK: - Identifiable Tests

  func testIdentifiable_usesIdProperty() {
    let handler = MockAttachmentHandler(id: "unique-id")
    XCTAssertEqual(handler.id, "unique-id")
  }

  func testIdentifiable_differentHandlersHaveDifferentIds() {
    let handler1 = MockAttachmentHandler(id: "handler-a")
    let handler2 = MockAttachmentHandler(id: "handler-b")

    XCTAssertNotEqual(handler1.id, handler2.id)
  }

  func testIdentifiable_canBeUsedInCollections() {
    let handler = MockAttachmentHandler(id: "collection-test")

    // Can be used in contexts requiring Identifiable
    let handlers: [any AttachmentHandler] = [handler]
    XCTAssertEqual(handlers.count, 1)
  }

  // MARK: - Sendable Tests

  func testSendable_handlerCanBeSentAcrossActors() async {
    let handler = MockAttachmentHandler(id: "sendable-test")

    let result = await withCheckedContinuation { continuation in
      Task.detached {
        // Accessing handler from detached task verifies Sendable
        continuation.resume(returning: handler.id)
      }
    }

    XCTAssertEqual(result, "sendable-test")
  }

  // MARK: - Call Tracking Tests

  func testCallTracking_tracksGenerateThumbnailCalls() async throws {
    let handler = MockAttachmentHandler()

    XCTAssertEqual(handler.generateThumbnailCallCount, 0)

    _ = try await handler.generateThumbnail(
      filePath: "/path1", maxSize: CGSize(width: 100, height: 100))
    XCTAssertEqual(handler.generateThumbnailCallCount, 1)

    _ = try await handler.generateThumbnail(
      filePath: "/path2", maxSize: CGSize(width: 200, height: 200))
    XCTAssertEqual(handler.generateThumbnailCallCount, 2)
  }

  func testCallTracking_tracksExtractMetadataCalls() async throws {
    let handler = MockAttachmentHandler()

    XCTAssertEqual(handler.extractMetadataCallCount, 0)

    _ = try await handler.extractMetadata(filePath: "/path1")
    XCTAssertEqual(handler.extractMetadataCallCount, 1)

    _ = try await handler.extractMetadata(filePath: "/path2")
    XCTAssertEqual(handler.extractMetadataCallCount, 2)
  }
}
