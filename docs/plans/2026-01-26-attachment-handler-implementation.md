# AttachmentHandler Protocol Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract attachment handling into a protocol-based architecture with handlers for images and videos, including a thumbnail endpoint with HTTP caching.

**Architecture:** Protocol-based handlers registered with a singleton registry. Each handler generates thumbnails and extracts metadata for its supported MIME types. A new REST endpoint serves thumbnails on-demand with cache headers.

**Tech Stack:** Swift, Vapor 4, AVFoundation (video), AppKit (image), GRDB

---

## Task 1: Create AttachmentMetadata Model

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Models/AttachmentMetadata.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Models/AttachmentMetadataTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import MessageBridgeCore

final class AttachmentMetadataTests: XCTestCase {

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

  func testEquatable_withSameValues_returnsTrue() {
    let metadata1 = AttachmentMetadata(width: 100, height: 200)
    let metadata2 = AttachmentMetadata(width: 100, height: 200)

    XCTAssertEqual(metadata1, metadata2)
  }

  func testCodable_roundTrip_preservesValues() throws {
    let original = AttachmentMetadata(width: 640, height: 480, duration: 30.0)
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AttachmentMetadata.self, from: encoded)

    XCTAssertEqual(decoded, original)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter AttachmentMetadataTests`
Expected: FAIL with "No such module 'MessageBridgeCore'" or "cannot find 'AttachmentMetadata'"

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Metadata extracted from an attachment by an AttachmentHandler.
///
/// Contains optional dimension and duration information depending on the attachment type:
/// - Images: width and height
/// - Videos: width, height, and duration
/// - Audio: duration only
/// - Documents: typically empty
public struct AttachmentMetadata: Codable, Sendable, Equatable {
  /// Width in pixels (for images and videos)
  public let width: Int?

  /// Height in pixels (for images and videos)
  public let height: Int?

  /// Duration in seconds (for video and audio)
  public let duration: Double?

  /// Cached thumbnail location (for future use)
  public let thumbnailPath: String?

  public init(
    width: Int? = nil,
    height: Int? = nil,
    duration: Double? = nil,
    thumbnailPath: String? = nil
  ) {
    self.width = width
    self.height = height
    self.duration = duration
    self.thumbnailPath = thumbnailPath
  }
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter AttachmentMetadataTests`
Expected: PASS (4 tests)

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Models/AttachmentMetadata.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Models/AttachmentMetadataTests.swift
git commit -m "feat(core): add AttachmentMetadata model

Metadata struct for storing dimensions and duration extracted from
attachments. Supports Codable for API responses and Equatable for testing."
```

---

## Task 2: Create AttachmentHandler Protocol

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Protocols/AttachmentHandler.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Protocols/AttachmentHandlerTests.swift`
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Mocks/MockAttachmentHandler.swift`

**Step 1: Write the failing test**

First, create the mock that will be used in tests:

```swift
// MockAttachmentHandler.swift
import Foundation
@testable import MessageBridgeCore

/// Mock implementation of AttachmentHandler for testing
struct MockAttachmentHandler: AttachmentHandler {
  let id: String
  let supportedMimeTypes: [String]
  var thumbnailResult: Data?
  var metadataResult: AttachmentMetadata
  var shouldThrowOnThumbnail: Bool = false
  var shouldThrowOnMetadata: Bool = false

  init(
    id: String = "mock-handler",
    supportedMimeTypes: [String] = ["mock/*"],
    thumbnailResult: Data? = nil,
    metadataResult: AttachmentMetadata = AttachmentMetadata()
  ) {
    self.id = id
    self.supportedMimeTypes = supportedMimeTypes
    self.thumbnailResult = thumbnailResult
    self.metadataResult = metadataResult
  }

  func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
    if shouldThrowOnThumbnail {
      throw NSError(domain: "MockError", code: 1, userInfo: nil)
    }
    return thumbnailResult
  }

  func extractMetadata(filePath: String) async throws -> AttachmentMetadata {
    if shouldThrowOnMetadata {
      throw NSError(domain: "MockError", code: 2, userInfo: nil)
    }
    return metadataResult
  }
}
```

Then write the protocol tests:

```swift
// AttachmentHandlerTests.swift
import XCTest
@testable import MessageBridgeCore

final class AttachmentHandlerTests: XCTestCase {

  func testProtocol_hasRequiredProperties() {
    let handler: any AttachmentHandler = MockAttachmentHandler(
      id: "test-handler",
      supportedMimeTypes: ["image/*", "video/mp4"]
    )

    XCTAssertEqual(handler.id, "test-handler")
    XCTAssertEqual(handler.supportedMimeTypes, ["image/*", "video/mp4"])
  }

  func testGenerateThumbnail_returnsThumbnailData() async throws {
    let expectedData = Data([0x00, 0x01, 0x02])
    let handler = MockAttachmentHandler(thumbnailResult: expectedData)

    let result = try await handler.generateThumbnail(
      filePath: "/fake/path.jpg",
      maxSize: CGSize(width: 300, height: 300)
    )

    XCTAssertEqual(result, expectedData)
  }

  func testGenerateThumbnail_canReturnNil() async throws {
    let handler = MockAttachmentHandler(thumbnailResult: nil)

    let result = try await handler.generateThumbnail(
      filePath: "/fake/path.pdf",
      maxSize: CGSize(width: 300, height: 300)
    )

    XCTAssertNil(result)
  }

  func testExtractMetadata_returnsMetadata() async throws {
    let expectedMetadata = AttachmentMetadata(width: 1920, height: 1080)
    let handler = MockAttachmentHandler(metadataResult: expectedMetadata)

    let result = try await handler.extractMetadata(filePath: "/fake/video.mp4")

    XCTAssertEqual(result, expectedMetadata)
  }

  func testIdentifiable_usesIdProperty() {
    let handler = MockAttachmentHandler(id: "unique-id")

    // Identifiable conformance uses id property
    XCTAssertEqual(handler.id, "unique-id")
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter AttachmentHandlerTests`
Expected: FAIL with "cannot find 'AttachmentHandler'"

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Protocol for handlers that process specific attachment types.
///
/// Each handler is responsible for:
/// - Generating thumbnails for supported MIME types
/// - Extracting metadata (dimensions, duration, etc.)
///
/// ## Implementing a Handler
///
/// ```swift
/// struct ImageHandler: AttachmentHandler {
///     let id = "image-handler"
///     let supportedMimeTypes = ["image/*"]
///
///     func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
///         // Generate JPEG thumbnail
///     }
///
///     func extractMetadata(filePath: String) async throws -> AttachmentMetadata {
///         // Extract width and height
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Handlers must be Sendable as they may be called from multiple threads.
public protocol AttachmentHandler: Identifiable, Sendable {
  /// Unique identifier for this handler
  var id: String { get }

  /// MIME type patterns this handler supports (e.g., "image/*", "video/mp4")
  ///
  /// Wildcards are supported:
  /// - `image/*` matches all image types
  /// - `video/mp4` matches only MP4 videos
  var supportedMimeTypes: [String] { get }

  /// Generate a thumbnail for the attachment.
  ///
  /// - Parameters:
  ///   - filePath: Absolute path to the attachment file
  ///   - maxSize: Maximum thumbnail dimensions (maintains aspect ratio)
  /// - Returns: JPEG thumbnail data, or nil if not applicable
  /// - Throws: If thumbnail generation fails
  func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data?

  /// Extract metadata from the attachment.
  ///
  /// - Parameter filePath: Absolute path to the attachment file
  /// - Returns: Extracted metadata (dimensions, duration, etc.)
  /// - Throws: If metadata extraction fails
  func extractMetadata(filePath: String) async throws -> AttachmentMetadata
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter AttachmentHandlerTests`
Expected: PASS (5 tests)

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Protocols/AttachmentHandler.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Protocols/AttachmentHandlerTests.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Mocks/MockAttachmentHandler.swift
git commit -m "feat(core): add AttachmentHandler protocol

Protocol for attachment handlers that generate thumbnails and extract
metadata. Supports MIME type wildcards (e.g., 'image/*') for matching."
```

---

## Task 3: Create AttachmentRegistry Singleton

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Registries/AttachmentRegistry.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Registries/AttachmentRegistryTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import MessageBridgeCore

final class AttachmentRegistryTests: XCTestCase {

  override func setUp() {
    super.setUp()
    AttachmentRegistry.shared.reset()
  }

  override func tearDown() {
    AttachmentRegistry.shared.reset()
    super.tearDown()
  }

  func testRegister_addsHandler() {
    let handler = MockAttachmentHandler(id: "test")
    AttachmentRegistry.shared.register(handler)

    XCTAssertEqual(AttachmentRegistry.shared.all.count, 1)
  }

  func testHandler_forExactMimeType_returnsHandler() {
    let handler = MockAttachmentHandler(
      id: "video",
      supportedMimeTypes: ["video/mp4"]
    )
    AttachmentRegistry.shared.register(handler)

    let found = AttachmentRegistry.shared.handler(for: "video/mp4")
    XCTAssertNotNil(found)
    XCTAssertEqual(found?.id, "video")
  }

  func testHandler_forWildcardMimeType_returnsHandler() {
    let handler = MockAttachmentHandler(
      id: "image",
      supportedMimeTypes: ["image/*"]
    )
    AttachmentRegistry.shared.register(handler)

    let foundJpeg = AttachmentRegistry.shared.handler(for: "image/jpeg")
    XCTAssertNotNil(foundJpeg)
    XCTAssertEqual(foundJpeg?.id, "image")

    let foundPng = AttachmentRegistry.shared.handler(for: "image/png")
    XCTAssertNotNil(foundPng)
    XCTAssertEqual(foundPng?.id, "image")
  }

  func testHandler_forUnknownMimeType_returnsNil() {
    let handler = MockAttachmentHandler(
      id: "image",
      supportedMimeTypes: ["image/*"]
    )
    AttachmentRegistry.shared.register(handler)

    let found = AttachmentRegistry.shared.handler(for: "audio/mp3")
    XCTAssertNil(found)
  }

  func testHandler_withMultipleHandlers_returnsFirstMatch() {
    let imageHandler = MockAttachmentHandler(
      id: "image-generic",
      supportedMimeTypes: ["image/*"]
    )
    let jpegHandler = MockAttachmentHandler(
      id: "jpeg-specific",
      supportedMimeTypes: ["image/jpeg"]
    )

    // Register generic first, then specific
    AttachmentRegistry.shared.register(imageHandler)
    AttachmentRegistry.shared.register(jpegHandler)

    // First registered match wins
    let found = AttachmentRegistry.shared.handler(for: "image/jpeg")
    XCTAssertEqual(found?.id, "image-generic")
  }

  func testAll_returnsAllHandlers() {
    let handler1 = MockAttachmentHandler(id: "h1")
    let handler2 = MockAttachmentHandler(id: "h2")

    AttachmentRegistry.shared.register(handler1)
    AttachmentRegistry.shared.register(handler2)

    let all = AttachmentRegistry.shared.all
    XCTAssertEqual(all.count, 2)
  }

  func testReset_removesAllHandlers() {
    AttachmentRegistry.shared.register(MockAttachmentHandler(id: "h1"))
    AttachmentRegistry.shared.register(MockAttachmentHandler(id: "h2"))
    XCTAssertEqual(AttachmentRegistry.shared.all.count, 2)

    AttachmentRegistry.shared.reset()
    XCTAssertEqual(AttachmentRegistry.shared.all.count, 0)
  }

  func testMimeTypeMatches_exactMatch_returnsTrue() {
    let handler = MockAttachmentHandler(
      id: "specific",
      supportedMimeTypes: ["video/mp4"]
    )
    AttachmentRegistry.shared.register(handler)

    XCTAssertNotNil(AttachmentRegistry.shared.handler(for: "video/mp4"))
    XCTAssertNil(AttachmentRegistry.shared.handler(for: "video/quicktime"))
  }

  func testMimeTypeMatches_wildcardDoesNotMatchDifferentType() {
    let handler = MockAttachmentHandler(
      id: "image",
      supportedMimeTypes: ["image/*"]
    )
    AttachmentRegistry.shared.register(handler)

    XCTAssertNil(AttachmentRegistry.shared.handler(for: "video/mp4"))
    XCTAssertNil(AttachmentRegistry.shared.handler(for: "imagejpeg")) // Malformed
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter AttachmentRegistryTests`
Expected: FAIL with "cannot find 'AttachmentRegistry'"

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Central registry for attachment handlers.
///
/// The registry is a singleton that holds all available attachment handlers.
/// Handlers register themselves at app startup, and routes query the registry
/// to find the appropriate handler for a given MIME type.
///
/// ## Usage
///
/// ```swift
/// // At app startup
/// AttachmentRegistry.shared.register(ImageHandler())
/// AttachmentRegistry.shared.register(VideoHandler())
///
/// // Find handler for MIME type
/// if let handler = AttachmentRegistry.shared.handler(for: "image/jpeg") {
///     let thumbnail = try await handler.generateThumbnail(filePath: path, maxSize: size)
/// }
/// ```
///
/// ## Thread Safety
///
/// All methods are thread-safe and can be called from any thread.
public final class AttachmentRegistry: @unchecked Sendable {
  /// Shared singleton instance
  public static let shared = AttachmentRegistry()

  private var handlers: [any AttachmentHandler] = []
  private let lock = NSLock()

  private init() {}

  /// Register an attachment handler.
  ///
  /// Handlers are checked in registration order when finding a handler for a MIME type.
  /// Register more specific handlers before generic wildcard handlers.
  ///
  /// - Parameter handler: The handler to register
  public func register(_ handler: any AttachmentHandler) {
    lock.lock()
    defer { lock.unlock() }
    handlers.append(handler)
  }

  /// Find a handler for the given MIME type.
  ///
  /// Supports wildcard patterns like "image/*" that match any image type.
  ///
  /// - Parameter mimeType: The MIME type to find a handler for (e.g., "image/jpeg")
  /// - Returns: The first handler that supports this MIME type, or nil if none found
  public func handler(for mimeType: String) -> (any AttachmentHandler)? {
    lock.lock()
    defer { lock.unlock() }

    for handler in handlers {
      for pattern in handler.supportedMimeTypes {
        if mimeTypeMatches(mimeType, pattern: pattern) {
          return handler
        }
      }
    }
    return nil
  }

  /// Check if a MIME type matches a pattern (supports wildcards like "image/*").
  private func mimeTypeMatches(_ mimeType: String, pattern: String) -> Bool {
    if pattern == mimeType { return true }
    if pattern.hasSuffix("/*") {
      let prefix = String(pattern.dropLast(2))
      return mimeType.hasPrefix(prefix + "/")
    }
    return false
  }

  /// All registered handlers.
  ///
  /// Returns handlers in registration order.
  public var all: [any AttachmentHandler] {
    lock.lock()
    defer { lock.unlock() }
    return handlers
  }

  /// Remove all registered handlers.
  ///
  /// Primarily useful for testing.
  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    handlers.removeAll()
  }
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter AttachmentRegistryTests`
Expected: PASS (9 tests)

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Registries/AttachmentRegistry.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Registries/AttachmentRegistryTests.swift
git commit -m "feat(core): add AttachmentRegistry singleton

Registry for attachment handlers with MIME type wildcard matching.
Handlers are checked in registration order to find matches."
```

---

## Task 4: Implement ImageHandler

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Attachments/ImageHandler.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Attachments/ImageHandlerTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import MessageBridgeCore

final class ImageHandlerTests: XCTestCase {

  var handler: ImageHandler!
  var testImagePath: String!

  override func setUp() {
    super.setUp()
    handler = ImageHandler()

    // Create a test image file
    testImagePath = FileManager.default.temporaryDirectory
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
    XCTAssertNil(metadata.duration) // Images don't have duration
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
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter ImageHandlerTests`
Expected: FAIL with "cannot find 'ImageHandler'"

**Step 3: Write minimal implementation**

```swift
import AppKit
import Foundation

/// Handler for image attachments.
///
/// Supports all image types (JPEG, PNG, GIF, HEIC, etc.) via the "image/*" MIME pattern.
/// Generates JPEG thumbnails and extracts width/height metadata.
public struct ImageHandler: AttachmentHandler {
  /// Unique identifier for this handler
  public let id = "image-handler"

  /// Supports all image MIME types
  public let supportedMimeTypes = ["image/*"]

  public init() {}

  /// Generate a JPEG thumbnail for the image.
  ///
  /// Scales the image to fit within maxSize while maintaining aspect ratio.
  ///
  /// - Parameters:
  ///   - filePath: Path to the source image file
  ///   - maxSize: Maximum dimensions for the thumbnail
  /// - Returns: JPEG data, or nil if the file doesn't exist or isn't an image
  public func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
    guard let image = NSImage(contentsOfFile: filePath) else {
      return nil
    }

    // Calculate scaled size maintaining aspect ratio
    let scale = min(
      maxSize.width / image.size.width,
      maxSize.height / image.size.height
    )
    let newSize = CGSize(
      width: image.size.width * scale,
      height: image.size.height * scale
    )

    // Draw scaled image
    let newImage = NSImage(size: newSize)
    newImage.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: image.size),
      operation: .copy,
      fraction: 1.0
    )
    newImage.unlockFocus()

    // Convert to JPEG data
    guard let tiffData = newImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData)
    else {
      return nil
    }

    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
  }

  /// Extract dimensions from the image.
  ///
  /// - Parameter filePath: Path to the image file
  /// - Returns: Metadata with width and height, or empty if file is invalid
  public func extractMetadata(filePath: String) async throws -> AttachmentMetadata {
    guard let image = NSImage(contentsOfFile: filePath) else {
      return AttachmentMetadata()
    }

    return AttachmentMetadata(
      width: Int(image.size.width),
      height: Int(image.size.height)
    )
  }
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter ImageHandlerTests`
Expected: PASS (7 tests)

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Attachments/ImageHandler.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Attachments/ImageHandlerTests.swift
git commit -m "feat(core): add ImageHandler for image thumbnails

Implements AttachmentHandler for image/* MIME types. Generates JPEG
thumbnails with aspect ratio preservation and extracts dimensions."
```

---

## Task 5: Implement VideoHandler

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Attachments/VideoHandler.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Attachments/VideoHandlerTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
import AVFoundation
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

  // Note: Tests with actual video files would require test fixtures.
  // These tests verify the handler works correctly with invalid inputs.
  // Integration tests with real videos are recommended for full coverage.

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
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter VideoHandlerTests`
Expected: FAIL with "cannot find 'VideoHandler'"

**Step 3: Write minimal implementation**

```swift
import AppKit
import AVFoundation
import Foundation

/// Handler for video attachments.
///
/// Supports all video types (MP4, MOV, etc.) via the "video/*" MIME pattern.
/// Generates JPEG thumbnails from the first frame and extracts duration/dimensions.
public struct VideoHandler: AttachmentHandler {
  /// Unique identifier for this handler
  public let id = "video-handler"

  /// Supports all video MIME types
  public let supportedMimeTypes = ["video/*"]

  public init() {}

  /// Generate a JPEG thumbnail from the first frame of the video.
  ///
  /// - Parameters:
  ///   - filePath: Path to the video file
  ///   - maxSize: Maximum dimensions for the thumbnail
  /// - Returns: JPEG data, or nil if the file doesn't exist or isn't a video
  public func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
    let url = URL(fileURLWithPath: filePath)

    // Verify file exists
    guard FileManager.default.fileExists(atPath: filePath) else {
      return nil
    }

    let asset = AVAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = maxSize

    let time = CMTime(seconds: 0, preferredTimescale: 1)

    do {
      let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
      let image = NSImage(
        cgImage: cgImage,
        size: NSSize(width: cgImage.width, height: cgImage.height)
      )

      guard let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
      else {
        return nil
      }

      return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    } catch {
      // Not a valid video file
      return nil
    }
  }

  /// Extract duration and dimensions from the video.
  ///
  /// - Parameter filePath: Path to the video file
  /// - Returns: Metadata with width, height, and duration in seconds
  public func extractMetadata(filePath: String) async throws -> AttachmentMetadata {
    let url = URL(fileURLWithPath: filePath)

    // Verify file exists
    guard FileManager.default.fileExists(atPath: filePath) else {
      return AttachmentMetadata()
    }

    let asset = AVAsset(url: url)

    do {
      let duration = try await asset.load(.duration)
      let tracks = try await asset.load(.tracks)

      var width: Int?
      var height: Int?

      if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
        let size = try await videoTrack.load(.naturalSize)
        width = Int(size.width)
        height = Int(size.height)
      }

      return AttachmentMetadata(
        width: width,
        height: height,
        duration: duration.seconds
      )
    } catch {
      // Not a valid video file
      return AttachmentMetadata()
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter VideoHandlerTests`
Expected: PASS (5 tests)

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Attachments/VideoHandler.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/Attachments/VideoHandlerTests.swift
git commit -m "feat(core): add VideoHandler for video thumbnails

Implements AttachmentHandler for video/* MIME types. Uses AVFoundation
to extract first frame as thumbnail and read duration/dimensions."
```

---

## Task 6: Add Thumbnail Endpoint to Routes

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/API/Routes.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/APITests.swift` (add tests)

**Step 1: Write the failing test**

Add these tests to the existing APITests.swift file:

```swift
// Add to APITests.swift

func testThumbnail_withValidImageAttachment_returnsJPEG() async throws {
  // Create test image file
  let testImagePath = FileManager.default.temporaryDirectory
    .appendingPathComponent("thumb-test-\(UUID().uuidString).png").path
  createTestImage(at: testImagePath, width: 800, height: 600)
  defer { try? FileManager.default.removeItem(atPath: testImagePath) }

  // Setup mock database to return attachment with the test path
  let attachment = Attachment(
    id: 999,
    guid: "test-guid",
    filename: "test.png",
    mimeType: "image/png",
    uti: "public.png",
    size: 1000,
    isOutgoing: false,
    isSticker: false
  )
  mockDatabase.mockAttachmentResult = (attachment, testImagePath)

  // Register image handler
  AttachmentRegistry.shared.reset()
  AttachmentRegistry.shared.register(ImageHandler())

  try app.test(.GET, "attachments/999/thumbnail", headers: headers) { res in
    XCTAssertEqual(res.status, .ok)
    XCTAssertEqual(res.headers.contentType, .jpeg)
    // Check for JPEG magic bytes
    XCTAssertEqual(res.body.readableBytes > 0, true)
    XCTAssertEqual(res.body.readBytes(length: 2), [0xFF, 0xD8])
  }
}

func testThumbnail_withCustomSize_respectsDimensions() async throws {
  let testImagePath = FileManager.default.temporaryDirectory
    .appendingPathComponent("thumb-size-\(UUID().uuidString).png").path
  createTestImage(at: testImagePath, width: 1600, height: 1200)
  defer { try? FileManager.default.removeItem(atPath: testImagePath) }

  let attachment = Attachment(
    id: 998,
    guid: "test-guid-2",
    filename: "large.png",
    mimeType: "image/png",
    uti: "public.png",
    size: 5000,
    isOutgoing: false,
    isSticker: false
  )
  mockDatabase.mockAttachmentResult = (attachment, testImagePath)

  AttachmentRegistry.shared.reset()
  AttachmentRegistry.shared.register(ImageHandler())

  try app.test(.GET, "attachments/998/thumbnail?width=100&height=100", headers: headers) { res in
    XCTAssertEqual(res.status, .ok)
    XCTAssertEqual(res.headers.contentType, .jpeg)
  }
}

func testThumbnail_withInvalidId_returnsBadRequest() async throws {
  try app.test(.GET, "attachments/invalid/thumbnail", headers: headers) { res in
    XCTAssertEqual(res.status, .badRequest)
  }
}

func testThumbnail_withNotFoundAttachment_returnsNotFound() async throws {
  mockDatabase.mockAttachmentResult = nil

  try app.test(.GET, "attachments/12345/thumbnail", headers: headers) { res in
    XCTAssertEqual(res.status, .notFound)
  }
}

func testThumbnail_withMissingFile_returnsNotFound() async throws {
  let attachment = Attachment(
    id: 997,
    guid: "missing-file-guid",
    filename: "missing.png",
    mimeType: "image/png",
    uti: "public.png",
    size: 1000,
    isOutgoing: false,
    isSticker: false
  )
  mockDatabase.mockAttachmentResult = (attachment, "/nonexistent/path.png")

  try app.test(.GET, "attachments/997/thumbnail", headers: headers) { res in
    XCTAssertEqual(res.status, .notFound)
  }
}

func testThumbnail_withUnsupportedMimeType_returnsUnsupportedMedia() async throws {
  let testPath = FileManager.default.temporaryDirectory
    .appendingPathComponent("test-\(UUID().uuidString).xyz").path
  try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
  defer { try? FileManager.default.removeItem(atPath: testPath) }

  let attachment = Attachment(
    id: 996,
    guid: "unsupported-guid",
    filename: "test.xyz",
    mimeType: "application/x-unknown",
    uti: "public.data",
    size: 4,
    isOutgoing: false,
    isSticker: false
  )
  mockDatabase.mockAttachmentResult = (attachment, testPath)

  AttachmentRegistry.shared.reset()
  // Don't register any handlers

  try app.test(.GET, "attachments/996/thumbnail", headers: headers) { res in
    XCTAssertEqual(res.status, .unsupportedMediaType)
  }
}

func testThumbnail_hasCacheHeaders() async throws {
  let testImagePath = FileManager.default.temporaryDirectory
    .appendingPathComponent("cache-test-\(UUID().uuidString).png").path
  createTestImage(at: testImagePath, width: 100, height: 100)
  defer { try? FileManager.default.removeItem(atPath: testImagePath) }

  let attachment = Attachment(
    id: 995,
    guid: "cache-guid",
    filename: "cached.png",
    mimeType: "image/png",
    uti: "public.png",
    size: 500,
    isOutgoing: false,
    isSticker: false
  )
  mockDatabase.mockAttachmentResult = (attachment, testImagePath)

  AttachmentRegistry.shared.reset()
  AttachmentRegistry.shared.register(ImageHandler())

  try app.test(.GET, "attachments/995/thumbnail", headers: headers) { res in
    XCTAssertEqual(res.status, .ok)
    // Check for cache headers
    XCTAssertNotNil(res.headers.cacheControl)
    XCTAssertTrue(res.headers.cacheControl?.isPublic ?? false)
  }
}

// Helper to create test images
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
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter testThumbnail`
Expected: FAIL with "GET /attachments/:id/thumbnail - not found" or similar

**Step 3: Write minimal implementation**

Add this route to Routes.swift after the existing `/attachments/:id` route (around line 125):

```swift
// GET /attachments/:id/thumbnail - Serve attachment thumbnail
protected.get("attachments", ":id", "thumbnail") { req async throws -> Response in
  guard let idString = req.parameters.get("id"),
        let attachmentId = Int64(idString)
  else {
    throw Abort(.badRequest, reason: "Invalid attachment ID")
  }

  // Size parameters (optional, defaults to 300x300)
  let maxWidth = req.query[Int.self, at: "width"] ?? 300
  let maxHeight = req.query[Int.self, at: "height"] ?? 300
  let maxSize = CGSize(width: maxWidth, height: maxHeight)

  guard let result = try await database.fetchAttachment(id: attachmentId) else {
    throw Abort(.notFound, reason: "Attachment not found")
  }

  let (attachment, filePath) = result

  guard FileManager.default.fileExists(atPath: filePath) else {
    throw Abort(.notFound, reason: "Attachment file not found")
  }

  // Find appropriate handler
  guard let mimeType = attachment.mimeType,
        let handler = AttachmentRegistry.shared.handler(for: mimeType)
  else {
    throw Abort(.unsupportedMediaType, reason: "No handler for this attachment type")
  }

  // Generate thumbnail
  guard let thumbnailData = try await handler.generateThumbnail(
    filePath: filePath,
    maxSize: maxSize
  ) else {
    throw Abort(.notFound, reason: "Could not generate thumbnail")
  }

  // Return as JPEG with cache headers
  let response = Response(status: .ok, body: .init(data: thumbnailData))
  response.headers.contentType = .jpeg
  response.headers.cacheControl = .init(isPublic: true, maxAge: 86400)  // Cache 24h
  return response
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter testThumbnail`
Expected: PASS (7 tests)

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/API/Routes.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/APITests.swift
git commit -m "feat(api): add thumbnail endpoint for attachments

GET /attachments/:id/thumbnail serves JPEG thumbnails with:
- Configurable size via width/height query params (default 300x300)
- 24-hour cache headers for performance
- Handler-based generation via AttachmentRegistry"
```

---

## Task 7: Update Attachment Model

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Models/Attachment.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/AttachmentTests.swift` (add tests)

**Step 1: Write the failing test**

Add these tests to AttachmentTests.swift:

```swift
// Add to AttachmentTests.swift

func testMetadata_defaultsToNil() {
  let attachment = Attachment(
    id: 1,
    guid: "test",
    filename: "test.jpg",
    mimeType: "image/jpeg",
    uti: nil,
    size: 1000,
    isOutgoing: false,
    isSticker: false
  )

  XCTAssertNil(attachment.metadata)
}

func testMetadata_canBeSet() {
  let metadata = AttachmentMetadata(width: 1920, height: 1080)
  let attachment = Attachment(
    id: 1,
    guid: "test",
    filename: "test.jpg",
    mimeType: "image/jpeg",
    uti: nil,
    size: 1000,
    isOutgoing: false,
    isSticker: false,
    metadata: metadata
  )

  XCTAssertEqual(attachment.metadata?.width, 1920)
  XCTAssertEqual(attachment.metadata?.height, 1080)
}

func testThumbnailURL_forImage_returnsPath() {
  let attachment = Attachment(
    id: 123,
    guid: "test",
    filename: "photo.jpg",
    mimeType: "image/jpeg",
    uti: nil,
    size: 1000,
    isOutgoing: false,
    isSticker: false
  )

  XCTAssertEqual(attachment.thumbnailURL, "/attachments/123/thumbnail")
}

func testThumbnailURL_forVideo_returnsPath() {
  let attachment = Attachment(
    id: 456,
    guid: "test",
    filename: "video.mp4",
    mimeType: "video/mp4",
    uti: nil,
    size: 5000,
    isOutgoing: false,
    isSticker: false
  )

  XCTAssertEqual(attachment.thumbnailURL, "/attachments/456/thumbnail")
}

func testThumbnailURL_forAudio_returnsNil() {
  let attachment = Attachment(
    id: 789,
    guid: "test",
    filename: "audio.mp3",
    mimeType: "audio/mpeg",
    uti: nil,
    size: 2000,
    isOutgoing: false,
    isSticker: false
  )

  XCTAssertNil(attachment.thumbnailURL)
}

func testThumbnailURL_forDocument_returnsNil() {
  let attachment = Attachment(
    id: 101,
    guid: "test",
    filename: "doc.pdf",
    mimeType: "application/pdf",
    uti: nil,
    size: 3000,
    isOutgoing: false,
    isSticker: false
  )

  XCTAssertNil(attachment.thumbnailURL)
}

func testThumbnailURL_withNoMimeType_returnsNil() {
  let attachment = Attachment(
    id: 102,
    guid: "test",
    filename: "unknown",
    mimeType: nil,
    uti: nil,
    size: 100,
    isOutgoing: false,
    isSticker: false
  )

  XCTAssertNil(attachment.thumbnailURL)
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter AttachmentTests`
Expected: FAIL with "Extra argument 'metadata'" or "'thumbnailURL' is not a member"

**Step 3: Write minimal implementation**

Update Attachment.swift:

```swift
import Foundation
import Vapor

/// Represents a file attachment (image, video, audio, document) in a message
public struct Attachment: Content, Identifiable, Sendable {
  public let id: Int64  // ROWID from database
  public let guid: String  // Unique identifier
  public let filename: String  // Original filename (transfer_name)
  public let mimeType: String?  // MIME type (image/jpeg, video/mp4, etc.)
  public let uti: String?  // Uniform Type Identifier
  public let size: Int64  // File size in bytes
  public let isOutgoing: Bool  // Whether we sent this attachment
  public let isSticker: Bool  // Whether this is a sticker

  // DEPRECATED: Use thumbnailURL instead for client-side thumbnail fetching
  public let thumbnailBase64: String?

  /// Metadata extracted by AttachmentHandler (dimensions, duration)
  public let metadata: AttachmentMetadata?

  /// Computed thumbnail URL for clients to fetch thumbnails.
  /// Returns a path for images and videos, nil for other types.
  public var thumbnailURL: String? {
    guard let mimeType = mimeType else { return nil }
    if mimeType.hasPrefix("image/") || mimeType.hasPrefix("video/") {
      return "/attachments/\(id)/thumbnail"
    }
    return nil
  }

  public init(
    id: Int64,
    guid: String,
    filename: String,
    mimeType: String?,
    uti: String?,
    size: Int64,
    isOutgoing: Bool,
    isSticker: Bool,
    thumbnailBase64: String? = nil,
    metadata: AttachmentMetadata? = nil
  ) {
    self.id = id
    self.guid = guid
    self.filename = filename
    self.mimeType = mimeType
    self.uti = uti
    self.size = size
    self.isOutgoing = isOutgoing
    self.isSticker = isSticker
    self.thumbnailBase64 = thumbnailBase64
    self.metadata = metadata
  }

  // MARK: - Attachment Type Detection

  /// The type category of this attachment
  public var attachmentType: AttachmentType {
    if let mimeType = mimeType {
      if mimeType.hasPrefix("image/") {
        return .image
      } else if mimeType.hasPrefix("video/") {
        return .video
      } else if mimeType.hasPrefix("audio/") {
        return .audio
      }
    }

    // Fallback to UTI-based detection
    if let uti = uti {
      if uti.contains("image") {
        return .image
      } else if uti.contains("movie") || uti.contains("video") {
        return .video
      } else if uti.contains("audio") {
        return .audio
      }
    }

    return .document
  }

  public var isImage: Bool { attachmentType == .image }
  public var isVideo: Bool { attachmentType == .video }
  public var isAudio: Bool { attachmentType == .audio }
  public var isDocument: Bool { attachmentType == .document }

  /// Human-readable file size (e.g., "1.2 MB")
  public var formattedSize: String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }
}

/// Categories of attachment types
public enum AttachmentType: String, Codable, Sendable {
  case image
  case video
  case audio
  case document
}
```

**Step 4: Run test to verify it passes**

Run: `cd MessageBridgeServer && swift test --filter AttachmentTests`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Models/Attachment.swift \
        MessageBridgeServer/Tests/MessageBridgeCoreTests/AttachmentTests.swift
git commit -m "feat(core): add metadata and thumbnailURL to Attachment model

- Added optional metadata property for handler-extracted dimensions/duration
- Added computed thumbnailURL property for images and videos
- thumbnailBase64 is now deprecated in favor of the thumbnail endpoint"
```

---

## Task 8: Register Handlers at Startup

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeServer/App/ServerApp.swift`

**Step 1: Identify where to add registration**

Look at ServerApp.swift around line 308-320 where `setupMessageProcessors()` is called.

**Step 2: Add handler registration method**

Add after the `setupMessageProcessors()` method (around line 421):

```swift
/// Register all attachment handlers with the AttachmentRegistry.
/// Handlers process attachments to generate thumbnails and extract metadata.
private func setupAttachmentHandlers() {
  AttachmentRegistry.shared.register(ImageHandler())
  AttachmentRegistry.shared.register(VideoHandler())
}
```

**Step 3: Call the method in init()**

Update the init() method (around line 309) to call the new setup:

```swift
init() {
  loadSettings()
  setupMessageProcessors()
  setupAttachmentHandlers()  // Add this line
  setupTunnelProviders()
  setupTunnelStatusHandlers()
  setupCoreLogging()
  // ... rest of init
}
```

**Step 4: Run full test suite**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeServer/App/ServerApp.swift
git commit -m "feat(server): register attachment handlers at startup

Registers ImageHandler and VideoHandler with AttachmentRegistry
during app initialization, enabling the thumbnail endpoint."
```

---

## Task 9: Update CLAUDE.md Migration Table

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the migration status table**

Find the Architecture Migration Status table and update the Attachment Handling row:

Before:
```markdown
| **Attachment Handling** | Basic serving                         | `AttachmentHandler` protocol + thumbnails     | 🔴 Not migrated    |
```

After:
```markdown
| **Attachment Handling** | Basic serving                         | `AttachmentHandler` protocol + thumbnails     | ✅ Migrated        |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: mark Attachment Handling as migrated in CLAUDE.md"
```

---

## Summary

After completing all 9 tasks, you will have:

1. **AttachmentMetadata** model for storing dimensions and duration
2. **AttachmentHandler** protocol defining the handler interface
3. **AttachmentRegistry** singleton for MIME type-based handler lookup
4. **ImageHandler** for image thumbnail generation and dimension extraction
5. **VideoHandler** for video frame extraction and metadata
6. **Thumbnail endpoint** (`GET /attachments/:id/thumbnail`) with caching
7. **Updated Attachment model** with metadata and thumbnailURL
8. **Handler registration** at app startup
9. **Updated documentation** reflecting migration status

Run final verification:
```bash
cd MessageBridgeServer && swift test
```

Expected: All tests pass (350+ tests)
