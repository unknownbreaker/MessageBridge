# Attachments and URL Previews Implementation Plan

## Overview

This plan implements two features in phases:
- **Phase 1:** Attachment support (images, videos, files)
- **Phase 2:** URL link previews using LinkPresentation framework

---

## Phase 1: Attachments

### 1.1 Server: Attachment Model

**File:** `MessageBridgeServer/Sources/MessageBridgeCore/Models/Attachment.swift`

Create a new `Attachment` model based on chat.db schema:

```swift
public struct Attachment: Content, Identifiable, Sendable {
    public let id: Int64              // ROWID
    public let guid: String           // Unique identifier
    public let filename: String       // Original filename (transfer_name)
    public let mimeType: String?      // MIME type (image/jpeg, video/mp4, etc.)
    public let uti: String?           // Uniform Type Identifier
    public let size: Int64            // File size in bytes (total_bytes)
    public let isOutgoing: Bool       // Whether we sent it
    public let isSticker: Bool        // Whether it's a sticker

    // For inline display (images only, resized)
    public let thumbnailBase64: String?
}
```

**Attachment types to support:**
| Type | MIME Types | Display |
|------|------------|---------|
| Image | image/jpeg, image/png, image/gif, image/heic | Inline thumbnail, tap for full |
| Video | video/mp4, video/quicktime | Thumbnail with play icon |
| Audio | audio/mpeg, audio/m4a | Audio player widget |
| Document | application/pdf, etc. | File icon + name + size |
| Other | * | Generic file icon |

---

### 1.2 Server: Update Message Model

**File:** `MessageBridgeServer/Sources/MessageBridgeCore/Models/Message.swift`

Add attachments array to Message:

```swift
public struct Message: Content, Identifiable, Sendable {
    // ... existing fields ...
    public let attachments: [Attachment]  // NEW
}
```

---

### 1.3 Server: Database Queries

**File:** `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift`

Add methods to fetch attachments:

```swift
// Fetch attachments for a message
private func fetchAttachments(for messageId: Int64) throws -> [Attachment]

// Query:
// SELECT a.* FROM attachment a
// JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
// WHERE maj.message_id = ?
```

Update `fetchMessages` to include attachments for each message.

**Thumbnail generation:**
- For images, generate thumbnails (max 300x300) using `NSImage`/`CGImage`
- Store as base64 in the response
- Skip for large files or non-images

---

### 1.4 Server: Attachment Endpoint

**File:** `MessageBridgeServer/Sources/MessageBridgeCore/API/Routes.swift`

Add new endpoint to serve full attachment files:

```
GET /attachments/:id
Headers: X-API-Key (required)
Response: File stream with appropriate Content-Type
```

**Implementation details:**
- Authenticate request with API key
- Look up attachment by ID
- Expand `~` in filename to home directory
- Stream file with correct MIME type
- Support range requests for video seeking (optional)

---

### 1.5 Client: Update Message Model

**File:** `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/Models.swift`

Mirror the server's Attachment model:

```swift
public struct Attachment: Codable, Identifiable, Sendable {
    public let id: Int64
    public let guid: String
    public let filename: String
    public let mimeType: String?
    public let uti: String?
    public let size: Int64
    public let isOutgoing: Bool
    public let isSticker: Bool
    public let thumbnailBase64: String?

    // Computed properties
    public var thumbnailData: Data? { ... }
    public var isImage: Bool { ... }
    public var isVideo: Bool { ... }
    public var isAudio: Bool { ... }
    public var formattedSize: String { ... }  // "1.2 MB"
}

public struct Message: Codable, Identifiable, Sendable {
    // ... existing fields ...
    public let attachments: [Attachment]  // NEW (default to empty array)
}
```

---

### 1.6 Client: Attachment Views

**File:** `MessageBridgeClient/Sources/MessageBridgeClient/Views/AttachmentView.swift`

Create views for displaying attachments:

```swift
struct AttachmentView: View {
    let attachment: Attachment

    var body: some View {
        switch attachment.attachmentType {
        case .image:
            ImageAttachmentView(attachment: attachment)
        case .video:
            VideoAttachmentView(attachment: attachment)
        case .audio:
            AudioAttachmentView(attachment: attachment)
        case .document:
            DocumentAttachmentView(attachment: attachment)
        }
    }
}

struct ImageAttachmentView: View {
    // Shows thumbnail, tap to open full image
    // Full image fetched from /attachments/:id endpoint
}

struct VideoAttachmentView: View {
    // Shows thumbnail with play button
    // Tap to play in AVPlayer
}

struct DocumentAttachmentView: View {
    // Shows file icon, name, size
    // Tap to download/open
}
```

---

### 1.7 Client: Integrate into Message Thread

**File:** `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift`

Update `MessageBubble` to display attachments:

```swift
struct MessageBubble: View {
    let message: Message

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading) {
            // Attachments first (like Apple Messages)
            ForEach(message.attachments) { attachment in
                AttachmentView(attachment: attachment)
            }

            // Then text (if any)
            if let text = message.text, !text.isEmpty {
                Text(text)
                    // ... existing styling
            }
        }
    }
}
```

---

### 1.8 Client: Attachment Service

**File:** `MessageBridgeClient/Sources/MessageBridgeClientCore/Services/AttachmentService.swift`

Service to fetch full attachments:

```swift
actor AttachmentService {
    private let connection: BridgeConnection
    private var cache: [Int64: Data] = [:]  // In-memory cache

    func fetchAttachment(id: Int64) async throws -> Data
    func fetchAttachmentURL(id: Int64) -> URL  // For streaming video
}
```

---

### 1.9 Server: Tests

**File:** `MessageBridgeServer/Tests/MessageBridgeCoreTests/AttachmentTests.swift`

```swift
- testAttachmentModel_decodesCorrectly()
- testFetchAttachments_returnsAttachmentsForMessage()
- testAttachmentEndpoint_returnsFile()
- testAttachmentEndpoint_withoutAuth_returns401()
- testAttachmentEndpoint_notFound_returns404()
- testThumbnailGeneration_resizesImage()
```

---

### 1.10 Client: Tests

**File:** `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/AttachmentTests.swift`

```swift
- testAttachmentModel_isImage_returnsCorrectly()
- testAttachmentModel_formattedSize_formatsCorrectly()
- testAttachmentService_fetchAttachment_returnsData()
```

---

## Phase 2: URL Link Previews

### 2.1 Client: URL Detection

**File:** `MessageBridgeClient/Sources/MessageBridgeClientCore/Utilities/URLDetector.swift`

Utility to extract URLs from message text:

```swift
struct URLDetector {
    static func detectURLs(in text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        // ... extract and return URLs
    }
}
```

---

### 2.2 Client: Link Preview View

**File:** `MessageBridgeClient/Sources/MessageBridgeClient/Views/LinkPreviewView.swift`

Use Apple's `LinkPresentation` framework:

```swift
import LinkPresentation

struct LinkPreviewView: View {
    let url: URL
    @State private var metadata: LPLinkMetadata?

    var body: some View {
        Group {
            if let metadata = metadata {
                LinkPreviewCard(metadata: metadata)
            } else {
                // Loading placeholder or compact URL
                Text(url.host ?? url.absoluteString)
            }
        }
        .task {
            await fetchMetadata()
        }
    }

    private func fetchMetadata() async {
        let provider = LPMetadataProvider()
        metadata = try? await provider.startFetchingMetadata(for: url)
    }
}

// SwiftUI wrapper for LPLinkView
struct LinkPreviewCard: NSViewRepresentable {
    let metadata: LPLinkMetadata

    func makeNSView(context: Context) -> LPLinkView {
        let view = LPLinkView(metadata: metadata)
        return view
    }

    func updateNSView(_ nsView: LPLinkView, context: Context) {
        nsView.metadata = metadata
    }
}
```

---

### 2.3 Client: Link Preview Cache

**File:** `MessageBridgeClient/Sources/MessageBridgeClientCore/Services/LinkPreviewCache.swift`

Cache fetched metadata to avoid refetching:

```swift
actor LinkPreviewCache {
    static let shared = LinkPreviewCache()

    private var cache: [URL: LPLinkMetadata] = [:]

    func metadata(for url: URL) -> LPLinkMetadata?
    func store(_ metadata: LPLinkMetadata, for url: URL)
}
```

---

### 2.4 Client: Integrate into Message Bubble

**File:** `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift`

Update `MessageBubble` to show link previews:

```swift
struct MessageBubble: View {
    let message: Message

    private var detectedURLs: [URL] {
        guard let text = message.text else { return [] }
        return URLDetector.detectURLs(in: text)
    }

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading) {
            // Attachments
            ForEach(message.attachments) { attachment in
                AttachmentView(attachment: attachment)
            }

            // Text
            if let text = message.text, !text.isEmpty {
                Text(text)
            }

            // Link previews (show first URL only, like Messages)
            if let firstURL = detectedURLs.first {
                LinkPreviewView(url: firstURL)
                    .frame(maxWidth: 280)
            }
        }
    }
}
```

---

### 2.5 Client: Tests

**File:** `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/URLDetectorTests.swift`

```swift
- testDetectURLs_findsHTTPLinks()
- testDetectURLs_findsHTTPSLinks()
- testDetectURLs_handlesMultipleLinks()
- testDetectURLs_ignoresInvalidURLs()
- testDetectURLs_handlesTextWithNoLinks()
```

---

## Version Bumps

After each phase completion:
- **Phase 1 complete:** Bump to 0.5.0 (feature: attachments)
- **Phase 2 complete:** Bump to 0.6.0 (feature: link previews)

---

## Task Summary

### Phase 1: Attachments (11 tasks)
1. Create Attachment model (server)
2. Update Message model to include attachments (server)
3. Add attachment query methods to ChatDatabase (server)
4. Add thumbnail generation for images (server)
5. Create /attachments/:id endpoint (server)
6. Write server tests for attachments
7. Create Attachment model (client)
8. Update Message model (client)
9. Create AttachmentView components (client)
10. Create AttachmentService for fetching full files (client)
11. Write client tests for attachments

### Phase 2: URL Previews (5 tasks)
1. Create URLDetector utility (client)
2. Create LinkPreviewView using LinkPresentation (client)
3. Create LinkPreviewCache (client)
4. Integrate link previews into MessageBubble (client)
5. Write tests for URL detection

---

## Notes

**Performance considerations:**
- Thumbnails keep API responses small
- Full attachments fetched on-demand
- Link previews fetched lazily and cached
- Consider disk cache for attachments in future

**Security:**
- Attachment endpoint requires API key
- Validate attachment IDs exist before serving
- Don't expose file system paths to client

**Future enhancements:**
- Disk-based attachment cache
- Video streaming with range requests
- Attachment search
- Drag-and-drop to save attachments
