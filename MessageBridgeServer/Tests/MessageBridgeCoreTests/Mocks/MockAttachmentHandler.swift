import Foundation

@testable import MessageBridgeCore

/// Mock attachment handler for testing
///
/// This mock allows configuring the thumbnail and metadata results,
/// making it easy to test different scenarios including success and error cases.
/// It uses a class to allow tracking call counts and parameters without requiring
/// mutating protocol methods.
///
/// ## Usage
///
/// ```swift
/// // Create a handler that returns specific results
/// let handler = MockAttachmentHandler(
///     id: "image-handler",
///     supportedMimeTypes: ["image/*"],
///     thumbnailResult: thumbnailData,
///     metadataResult: AttachmentMetadata(width: 1920, height: 1080)
/// )
///
/// let thumbnail = try await handler.generateThumbnail(filePath: "/path", maxSize: CGSize(width: 300, height: 300))
/// let metadata = try await handler.extractMetadata(filePath: "/path")
///
/// // Verify calls
/// XCTAssertEqual(handler.generateThumbnailCallCount, 1)
///
/// // Test error scenarios
/// handler.shouldThrowOnThumbnail = true
/// // Now generateThumbnail will throw
/// ```
public final class MockAttachmentHandler: AttachmentHandler, @unchecked Sendable {
  public let id: String
  public let supportedMimeTypes: [String]

  /// The data to return from `generateThumbnail`. If nil, returns nil (no thumbnail).
  public var thumbnailResult: Data?

  /// The metadata to return from `extractMetadata`.
  public var metadataResult: AttachmentMetadata

  /// If true, `generateThumbnail` will throw an error.
  public var shouldThrowOnThumbnail: Bool

  /// If true, `extractMetadata` will throw an error.
  public var shouldThrowOnMetadata: Bool

  /// Track calls for verification in tests
  public private(set) var generateThumbnailCallCount: Int = 0
  public private(set) var extractMetadataCallCount: Int = 0
  public private(set) var lastThumbnailFilePath: String?
  public private(set) var lastThumbnailMaxSize: CGSize?
  public private(set) var lastMetadataFilePath: String?

  /// Creates a mock attachment handler with configurable behavior.
  ///
  /// - Parameters:
  ///   - id: Unique identifier for this handler
  ///   - supportedMimeTypes: MIME type patterns this handler supports
  ///   - thumbnailResult: Data to return from generateThumbnail (nil = no thumbnail)
  ///   - metadataResult: Metadata to return from extractMetadata
  ///   - shouldThrowOnThumbnail: If true, generateThumbnail throws
  ///   - shouldThrowOnMetadata: If true, extractMetadata throws
  public init(
    id: String = "mock-handler",
    supportedMimeTypes: [String] = ["mock/*"],
    thumbnailResult: Data? = nil,
    metadataResult: AttachmentMetadata = AttachmentMetadata(),
    shouldThrowOnThumbnail: Bool = false,
    shouldThrowOnMetadata: Bool = false
  ) {
    self.id = id
    self.supportedMimeTypes = supportedMimeTypes
    self.thumbnailResult = thumbnailResult
    self.metadataResult = metadataResult
    self.shouldThrowOnThumbnail = shouldThrowOnThumbnail
    self.shouldThrowOnMetadata = shouldThrowOnMetadata
  }

  public func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
    generateThumbnailCallCount += 1
    lastThumbnailFilePath = filePath
    lastThumbnailMaxSize = maxSize

    if shouldThrowOnThumbnail {
      throw MockAttachmentHandlerError.thumbnailGenerationFailed
    }
    return thumbnailResult
  }

  public func extractMetadata(filePath: String) async throws -> AttachmentMetadata {
    extractMetadataCallCount += 1
    lastMetadataFilePath = filePath

    if shouldThrowOnMetadata {
      throw MockAttachmentHandlerError.metadataExtractionFailed
    }
    return metadataResult
  }
}

/// Errors thrown by MockAttachmentHandler when configured to fail
public enum MockAttachmentHandlerError: Error, LocalizedError {
  case thumbnailGenerationFailed
  case metadataExtractionFailed

  public var errorDescription: String? {
    switch self {
    case .thumbnailGenerationFailed:
      return "Mock thumbnail generation failed"
    case .metadataExtractionFailed:
      return "Mock metadata extraction failed"
    }
  }
}
