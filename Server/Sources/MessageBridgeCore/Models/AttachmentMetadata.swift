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
