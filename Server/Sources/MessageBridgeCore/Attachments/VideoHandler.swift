import AVFoundation
import AppKit
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
