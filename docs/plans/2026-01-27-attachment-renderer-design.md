# AttachmentRenderer Protocol Design

**Date:** 2026-01-27
**Status:** Approved
**Goal:** Extract attachment rendering from the hardcoded switch in AttachmentView into a protocol-based architecture with group-aware renderers and image gallery support.

---

## Problem

AttachmentView uses a hardcoded switch on 4 attachment types (image, video, audio, document). Adding new rendering modes (gallery grid, carousel, contact cards) requires modifying the switch. No way to render multiple attachments as a group (e.g., image gallery).

## Design Goals

1. **Group-aware** — Renderers receive all attachments, enabling gallery/grid layouts
2. **Extensible** — Protocol-based, easy to add new renderers
3. **Non-breaking** — Wraps existing attachment views initially
4. **Consistent** — Same pattern as MessageRenderer + RendererRegistry

## Scope

**In scope (v1):**
- AttachmentRenderer protocol (group-based)
- AttachmentRendererRegistry singleton
- SingleImageRenderer (wraps existing ImageAttachmentView)
- VideoRenderer (wraps existing VideoAttachmentView)
- AudioRenderer (wraps existing AudioAttachmentView)
- DocumentRenderer (wraps existing DocumentAttachmentView, fallback)
- ImageGalleryRenderer (new — 2+ images in grid layout)
- MessageBubble integration

**Out of scope (future):**
- Carousel/fullscreen swipe navigation
- Contact card renderer
- Location renderer
- Sticker renderer

---

## Core Types

### AttachmentRenderer Protocol

```swift
// Sources/MessageBridgeClientCore/Protocols/AttachmentRenderer.swift

import SwiftUI

public protocol AttachmentRenderer: Identifiable, Sendable {
    /// Unique identifier for this renderer
    var id: String { get }

    /// Priority for selection. Higher = checked first.
    var priority: Int { get }

    /// Can this renderer handle this group of attachments?
    func canRender(_ attachments: [Attachment]) -> Bool

    /// Render the attachment group.
    @MainActor func render(_ attachments: [Attachment]) -> AnyView
}
```

### AttachmentRendererRegistry

```swift
// Sources/MessageBridgeClientCore/Registries/AttachmentRendererRegistry.swift

public final class AttachmentRendererRegistry: @unchecked Sendable {
    public static let shared = AttachmentRendererRegistry()

    private var renderers: [any AttachmentRenderer] = []
    private let lock = NSLock()

    private init() {}

    public func register(_ renderer: any AttachmentRenderer) {
        lock.lock()
        defer { lock.unlock() }
        renderers.append(renderer)
    }

    public func renderer(for attachments: [Attachment]) -> any AttachmentRenderer {
        lock.lock()
        defer { lock.unlock() }
        return renderers
            .sorted { $0.priority > $1.priority }
            .first { $0.canRender(attachments) }
            ?? DocumentRenderer()
    }

    public var all: [any AttachmentRenderer] {
        lock.lock()
        defer { lock.unlock() }
        return renderers
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        renderers.removeAll()
    }
}
```

---

## Renderer Implementations

### DocumentRenderer (priority: 0, fallback)

```swift
public struct DocumentRenderer: AttachmentRenderer {
    public let id = "document"
    public let priority = 0

    public func canRender(_ attachments: [Attachment]) -> Bool {
        true  // Fallback — renders anything
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        AnyView(
            ForEach(attachments) { attachment in
                DocumentAttachmentView(attachment: attachment)
            }
        )
    }
}
```

### SingleImageRenderer (priority: 50)

```swift
public struct SingleImageRenderer: AttachmentRenderer {
    public let id = "single-image"
    public let priority = 50

    public func canRender(_ attachments: [Attachment]) -> Bool {
        attachments.count == 1 && attachments[0].isImage
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        AnyView(
            ImageAttachmentView(attachment: attachments[0])
        )
    }
}
```

### VideoRenderer (priority: 50)

```swift
public struct VideoRenderer: AttachmentRenderer {
    public let id = "video"
    public let priority = 50

    public func canRender(_ attachments: [Attachment]) -> Bool {
        attachments.allSatisfy { $0.isVideo }
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        AnyView(
            ForEach(attachments) { attachment in
                VideoAttachmentView(attachment: attachment)
            }
        )
    }
}
```

### AudioRenderer (priority: 50)

```swift
public struct AudioRenderer: AttachmentRenderer {
    public let id = "audio"
    public let priority = 50

    public func canRender(_ attachments: [Attachment]) -> Bool {
        attachments.allSatisfy { $0.isAudio }
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        AnyView(
            ForEach(attachments) { attachment in
                AudioAttachmentView(attachment: attachment)
            }
        )
    }
}
```

### ImageGalleryRenderer (priority: 100)

```swift
public struct ImageGalleryRenderer: AttachmentRenderer {
    public let id = "image-gallery"
    public let priority = 100

    public func canRender(_ attachments: [Attachment]) -> Bool {
        let images = attachments.filter { $0.isImage }
        return images.count >= 2
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        let images = attachments.filter { $0.isImage }
        let nonImages = attachments.filter { !$0.isImage }

        return AnyView(
            VStack(spacing: 4) {
                ImageGridView(attachments: images)
                // Render non-image attachments below the grid
                ForEach(nonImages) { attachment in
                    // Fall through to individual rendering
                    AttachmentRendererRegistry.shared
                        .renderer(for: [attachment])
                        .render([attachment])
                }
            }
        )
    }
}
```

**ImageGridView** — new view for grid layout:

```swift
struct ImageGridView: View {
    let attachments: [Attachment]
    private let maxDisplay = 4

    var body: some View {
        let displayAttachments = Array(attachments.prefix(maxDisplay))
        let overflow = attachments.count - maxDisplay

        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(displayAttachments.enumerated()), id: \.element.id) { index, attachment in
                ZStack {
                    ImageThumbnailView(attachment: attachment)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()

                    // Show +N overlay on last cell if overflow
                    if index == maxDisplay - 1 && overflow > 0 {
                        Color.black.opacity(0.5)
                        Text("+\(overflow)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(maxWidth: 280)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var columns: [GridItem] {
        let count = min(attachments.count, maxDisplay)
        let columnCount = count <= 1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
    }
}
```

---

## Integration

### MessageBubble Change

```swift
// OLD:
if message.hasAttachments {
    ForEach(message.attachments) { attachment in
        AttachmentView(attachment: attachment)
    }
}

// NEW:
if message.hasAttachments {
    AttachmentRendererRegistry.shared.renderer(for: message.attachments)
        .render(message.attachments)
}
```

### App Registration

```swift
func setupAttachmentRenderers() {
    AttachmentRendererRegistry.shared.register(DocumentRenderer())
    AttachmentRendererRegistry.shared.register(SingleImageRenderer())
    AttachmentRendererRegistry.shared.register(VideoRenderer())
    AttachmentRendererRegistry.shared.register(AudioRenderer())
    AttachmentRendererRegistry.shared.register(ImageGalleryRenderer())
}
```

---

## File Structure

**New files:**

```
MessageBridgeClient/Sources/MessageBridgeClientCore/
├── Protocols/
│   └── AttachmentRenderer.swift
├── Registries/
│   └── AttachmentRendererRegistry.swift
└── Renderers/
    └── Attachments/
        ├── SingleImageRenderer.swift
        ├── ImageGalleryRenderer.swift
        ├── VideoRenderer.swift
        ├── AudioRenderer.swift
        └── DocumentRenderer.swift

Tests/MessageBridgeClientCoreTests/
├── Protocols/
│   └── AttachmentRendererTests.swift
├── Registries/
│   └── AttachmentRendererRegistryTests.swift
└── Renderers/
    ├── SingleImageRendererTests.swift
    ├── ImageGalleryRendererTests.swift
    ├── VideoRendererTests.swift
    ├── AudioRendererTests.swift
    └── DocumentRendererTests.swift
```

**Files to modify:**

| File | Change |
|------|--------|
| `MessageThreadView.swift` | Replace ForEach+AttachmentView with registry delegation |
| `MessageBridgeApp.swift` | Add setupAttachmentRenderers() |
| `CLAUDE.md` | Update migration table (Client Attachments → ✅) |

**Note:** Existing attachment views (ImageAttachmentView, VideoAttachmentView, AudioAttachmentView, DocumentAttachmentView) stay in AttachmentView.swift — renderers wrap them. They can be moved to individual files in a future cleanup.

---

## Future Extensions

**Adding CarouselRenderer:**

```swift
struct CarouselRenderer: AttachmentRenderer {
    let id = "carousel"
    let priority = 150  // Higher than gallery

    func canRender(_ attachments: [Attachment]) -> Bool {
        // Activate when user taps gallery to go fullscreen
        false  // Triggered by interaction, not auto-selected
    }
}
```

**Adding ContactRenderer:**

```swift
struct ContactRenderer: AttachmentRenderer {
    let id = "contact"
    let priority = 50

    func canRender(_ attachments: [Attachment]) -> Bool {
        attachments.count == 1 && attachments[0].mimeType == "text/vcard"
    }
}
```
