import Foundation
import Vapor

/// Represents a file attachment (image, video, audio, document) in a message
public struct Attachment: Content, Identifiable, Sendable {
    public let id: Int64                    // ROWID from database
    public let guid: String                 // Unique identifier
    public let filename: String             // Original filename (transfer_name)
    public let mimeType: String?            // MIME type (image/jpeg, video/mp4, etc.)
    public let uti: String?                 // Uniform Type Identifier
    public let size: Int64                  // File size in bytes
    public let isOutgoing: Bool             // Whether we sent this attachment
    public let isSticker: Bool              // Whether this is a sticker
    public let thumbnailBase64: String?     // Thumbnail image as base64 (for images/videos)

    public init(
        id: Int64,
        guid: String,
        filename: String,
        mimeType: String?,
        uti: String?,
        size: Int64,
        isOutgoing: Bool,
        isSticker: Bool,
        thumbnailBase64: String? = nil
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
