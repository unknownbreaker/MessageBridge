# AttachmentHandler Protocol Design

**Date:** 2026-01-26
**Status:** Approved
**Goal:** Extract attachment handling into a protocol-based architecture with handlers for different file types, following the same pattern as MessageProcessor/ProcessorChain.

---

## Problem

Attachments are currently served with inline base64 thumbnails and no extensibility for new attachment types. The handling logic is embedded in ChatDatabase and Routes, making it hard to:
- Add new attachment types (contact cards, locations)
- Customize thumbnail generation per type
- Extract rich metadata (video duration, image dimensions)
- Cache thumbnails efficiently

## Design Goals

1. **Extensible** — Protocol-based handlers, easy to add new types
2. **Performant** — Separate thumbnail endpoint with HTTP caching
3. **Consistent** — Same pattern as TunnelProvider and MessageProcessor
4. **Testable** — Each handler can be unit tested in isolation

## Scope

**In scope (v1):**
- AttachmentHandler protocol
- AttachmentRegistry singleton
- ImageHandler - thumbnail generation, dimension extraction
- VideoHandler - frame extraction, duration/dimension metadata
- Thumbnail endpoint (GET /attachments/:id/thumbnail)
- AttachmentMetadata model

**Out of scope (future):**
- AudioHandler - waveform generation
- FileHandler - document icons
- ContactHandler - vCard parsing
- LocationHandler - map previews
- Blurhash placeholders
- Thumbnail caching to disk

---

## Core Types

### AttachmentHandler Protocol

```swift
// Sources/MessageBridgeCore/Protocols/AttachmentHandler.swift

import Foundation

public protocol AttachmentHandler: Identifiable, Sendable {
    /// Unique identifier for this handler
    var id: String { get }

    /// MIME type patterns this handler supports (e.g., "image/*", "video/mp4")
    var supportedMimeTypes: [String] { get }

    /// Generate a thumbnail for the attachment
    /// - Parameters:
    ///   - filePath: Path to the attachment file
    ///   - maxSize: Maximum thumbnail dimensions
    /// - Returns: JPEG thumbnail data, or nil if not applicable
    func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data?

    /// Extract metadata from the attachment
    /// - Parameter filePath: Path to the attachment file
    /// - Returns: Extracted metadata
    func extractMetadata(filePath: String) async throws -> AttachmentMetadata
}
```

### AttachmentMetadata Model

```swift
// Sources/MessageBridgeCore/Models/AttachmentMetadata.swift

import Foundation

public struct AttachmentMetadata: Codable, Sendable, Equatable {
    public let width: Int?           // Images, videos
    public let height: Int?          // Images, videos
    public let duration: Double?     // Video, audio (seconds)
    public let thumbnailPath: String? // Cached thumbnail location (future)

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

---

## Registry

### AttachmentRegistry

```swift
// Sources/MessageBridgeCore/Registries/AttachmentRegistry.swift

import Foundation

public final class AttachmentRegistry: @unchecked Sendable {
    public static let shared = AttachmentRegistry()

    private var handlers: [any AttachmentHandler] = []
    private let lock = NSLock()

    private init() {}

    /// Register a handler
    public func register(_ handler: any AttachmentHandler) {
        lock.lock()
        defer { lock.unlock() }
        handlers.append(handler)
    }

    /// Find handler for a MIME type (e.g., "image/jpeg")
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

    /// Check if a MIME type matches a pattern (supports wildcards like "image/*")
    private func mimeTypeMatches(_ mimeType: String, pattern: String) -> Bool {
        if pattern == mimeType { return true }
        if pattern.hasSuffix("/*") {
            let prefix = String(pattern.dropLast(2))
            return mimeType.hasPrefix(prefix + "/")
        }
        return false
    }

    /// All registered handlers
    public var all: [any AttachmentHandler] {
        lock.lock()
        defer { lock.unlock() }
        return handlers
    }

    /// Reset for testing
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }
}
```

---

## Handler Implementations

### ImageHandler

```swift
// Sources/MessageBridgeCore/Attachments/ImageHandler.swift

import Foundation
import AppKit

public struct ImageHandler: AttachmentHandler {
    public let id = "image-handler"
    public let supportedMimeTypes = ["image/*"]

    public init() {}

    public func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
        guard let image = NSImage(contentsOfFile: filePath) else {
            return nil
        }

        // Calculate scaled size maintaining aspect ratio
        let scale = min(maxSize.width / image.size.width,
                        maxSize.height / image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        // Draw scaled image
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        newImage.unlockFocus()

        // Convert to JPEG data
        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

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

### VideoHandler

```swift
// Sources/MessageBridgeCore/Attachments/VideoHandler.swift

import Foundation
import AVFoundation
import AppKit

public struct VideoHandler: AttachmentHandler {
    public let id = "video-handler"
    public let supportedMimeTypes = ["video/*"]

    public init() {}

    public func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
        let url = URL(fileURLWithPath: filePath)
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize

        let time = CMTime(seconds: 0, preferredTimescale: 1)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    public func extractMetadata(filePath: String) async throws -> AttachmentMetadata {
        let url = URL(fileURLWithPath: filePath)
        let asset = AVAsset(url: url)

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
    }
}
```

---

## API Integration

### Thumbnail Route

```swift
// In Routes.swift - add new route

// GET /attachments/:id/thumbnail - Serve attachment thumbnail
protected.get("attachments", ":id", "thumbnail") { req async throws -> Response in
    guard let idString = req.parameters.get("id"),
          let attachmentId = Int64(idString)
    else {
        throw Abort(.badRequest, reason: "Invalid attachment ID")
    }

    // Size parameter (optional, defaults to 300x300)
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
          let handler = AttachmentRegistry.shared.handler(for: mimeType) else {
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
    response.headers.cacheControl = .init(isPublic: true, maxAge: 86400) // Cache 24h
    return response
}
```

### Attachment Model Changes

```swift
// In Attachment model

public struct Attachment: Codable, Sendable, Identifiable {
    // ... existing fields ...

    // REMOVE: public var thumbnailBase64: String?

    // ADD: Metadata extracted by handlers
    public var metadata: AttachmentMetadata?

    // ADD: Computed thumbnail URL for clients
    public var thumbnailURL: String? {
        guard let mimeType = mimeType else { return nil }
        if mimeType.hasPrefix("image/") || mimeType.hasPrefix("video/") {
            return "/attachments/\(id)/thumbnail"
        }
        return nil
    }
}
```

---

## File Structure

**New files:**

```
MessageBridgeServer/Sources/MessageBridgeCore/
├── Protocols/
│   └── AttachmentHandler.swift
├── Registries/
│   └── AttachmentRegistry.swift
├── Attachments/
│   ├── ImageHandler.swift
│   └── VideoHandler.swift
└── Models/
    └── AttachmentMetadata.swift

Tests/MessageBridgeCoreTests/
├── Attachments/
│   ├── AttachmentRegistryTests.swift
│   ├── ImageHandlerTests.swift
│   └── VideoHandlerTests.swift
└── API/
    └── ThumbnailRouteTests.swift
```

**Files to modify:**

| File | Change |
|------|--------|
| `Attachment.swift` | Remove thumbnailBase64, add metadata and thumbnailURL |
| `Routes.swift` | Add thumbnail endpoint |
| `ServerApp.swift` | Register handlers at startup |
| `ChatDatabase.swift` | Remove inline thumbnail generation |
| `CLAUDE.md` | Update migration table |

---

## Migration Steps

1. Create AttachmentMetadata model with tests
2. Create AttachmentHandler protocol
3. Create AttachmentRegistry singleton with tests
4. Implement ImageHandler with tests
5. Implement VideoHandler with tests
6. Add thumbnail route to Routes.swift
7. Update Attachment model (remove thumbnailBase64, add metadata/thumbnailURL)
8. Remove inline thumbnail generation from ChatDatabase
9. Register handlers in ServerApp.swift
10. Update client to use thumbnail URLs instead of base64
11. Update CLAUDE.md migration table

---

## Future Extensions

**Adding AudioHandler:**

```swift
struct AudioHandler: AttachmentHandler {
    let id = "audio-handler"
    let supportedMimeTypes = ["audio/*"]

    func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data? {
        // Return waveform visualization as image
    }

    func extractMetadata(filePath: String) async throws -> AttachmentMetadata {
        // Return duration
    }
}
```

**Adding thumbnail caching:**

```swift
// In AttachmentRegistry or dedicated ThumbnailCache
func getCachedThumbnail(attachmentId: Int64, size: CGSize) -> Data?
func cacheThumbnail(_ data: Data, attachmentId: Int64, size: CGSize)
```

**Adding blurhash placeholders:**

```swift
struct AttachmentMetadata {
    // ... existing fields ...
    public let blurhash: String?  // Compact placeholder representation
}
```
