import Foundation

/// Protocol for handlers that process specific attachment types.
///
/// Each handler is responsible for:
/// - Generating thumbnails for supported MIME types
/// - Extracting metadata (dimensions, duration, etc.)
///
/// Handlers are registered with the `AttachmentRegistry` and are matched
/// based on their `supportedMimeTypes`. MIME types can use wildcards
/// (e.g., "image/*" matches any image type).
///
/// ## Implementing a Handler
///
/// ```swift
/// struct ImageHandler: AttachmentHandler {
///     let id = "image-handler"
///     let supportedMimeTypes = ["image/*"]
///
///     func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
///         // Generate JPEG thumbnail from image at filePath
///         // Return nil if thumbnail cannot be generated
///     }
///
///     func extractMetadata(filePath: String) async throws -> AttachmentMetadata {
///         // Extract width and height from image
///         return AttachmentMetadata(width: 1920, height: 1080)
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Handlers must be Sendable as they may be called from multiple threads
/// concurrently. All methods are async to allow non-blocking I/O operations.
///
/// ## MIME Type Matching
///
/// The `supportedMimeTypes` array can contain:
/// - Specific types: "image/jpeg", "video/mp4"
/// - Wildcards: "image/*", "video/*"
/// - Multiple types: ["image/jpeg", "image/png", "image/gif"]
///
/// The registry uses these patterns to route attachments to the appropriate handler.
public protocol AttachmentHandler: Identifiable, Sendable {
  /// Unique identifier for this handler (e.g., "image-handler", "video-handler")
  var id: String { get }

  /// MIME type patterns this handler supports.
  ///
  /// Examples:
  /// - `["image/*"]` - All image types
  /// - `["video/mp4", "video/quicktime"]` - Specific video types
  /// - `["application/pdf"]` - PDF documents only
  var supportedMimeTypes: [String] { get }

  /// Generate a thumbnail for the attachment at the given path.
  ///
  /// - Parameters:
  ///   - filePath: Absolute path to the attachment file
  ///   - maxSize: Maximum dimensions for the thumbnail (will maintain aspect ratio)
  /// - Returns: JPEG thumbnail data, or nil if thumbnail cannot be generated
  /// - Throws: If an error occurs reading or processing the file
  func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data?

  /// Extract metadata from the attachment at the given path.
  ///
  /// - Parameter filePath: Absolute path to the attachment file
  /// - Returns: Metadata about the attachment (dimensions, duration, etc.)
  /// - Throws: If an error occurs reading or processing the file
  func extractMetadata(filePath: String) async throws -> AttachmentMetadata
}
