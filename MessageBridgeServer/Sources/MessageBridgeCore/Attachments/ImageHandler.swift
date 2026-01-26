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
