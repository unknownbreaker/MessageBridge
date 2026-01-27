# MessageRenderer Protocol Design

**Date:** 2026-01-26
**Status:** Approved
**Goal:** Extract text/content rendering from the monolithic MessageBubble into a protocol-based architecture with priority-ordered renderers and a RendererRegistry.

---

## Problem

MessageBubble is a monolithic SwiftUI view with all rendering logic hardcoded inline:
- Plain text, link previews, large emoji, attachments, avatars, timestamps all in one view
- No way to add new rendering styles without modifying MessageBubble
- No support for server-side enrichments (detected codes, highlights)
- Adding features like code highlighting or rich text requires touching core UI code

## Design Goals

1. **Extensible** — Protocol-based renderers, easy to add new content types
2. **Priority-ordered** — Highest priority renderer that matches wins
3. **Non-breaking** — MessageBubble keeps its chrome (avatar, timestamp, layout); only content rendering is extracted
4. **Enrichment-aware** — Client Message model supports server-side ProcessedMessage fields

## Scope

**In scope (v1):**
- MessageRenderer protocol
- RendererRegistry singleton
- PlainTextRenderer (fallback, priority 0)
- LargeEmojiRenderer (priority 50)
- LinkPreviewRenderer (priority 100, wraps existing LinkPreviewView)
- CodeHighlightRenderer (priority 100, for detected verification codes)
- Client Message model additions (detectedCodes, highlights, linkPreviews)
- MessageBubble integration (delegate content to registry)

**Out of scope (future):**
- RenderContext protocol (selection state, carousel presentation)
- AttachmentRenderer protocol (separate migration)
- BubbleDecorator protocol (separate migration)
- Server-side link preview generation

---

## Core Types

### MessageRenderer Protocol

```swift
// Sources/MessageBridgeClientCore/Protocols/MessageRenderer.swift

import SwiftUI

public protocol MessageRenderer: Identifiable, Sendable {
    /// Unique identifier for this renderer
    var id: String { get }

    /// Priority for selection. Higher = checked first.
    var priority: Int { get }

    /// Can this renderer handle the message?
    func canRender(_ message: Message) -> Bool

    /// Render the message content (text area only, not bubble chrome)
    @MainActor func render(_ message: Message) -> AnyView
}
```

### RendererRegistry

```swift
// Sources/MessageBridgeClientCore/Registries/RendererRegistry.swift

public final class RendererRegistry: @unchecked Sendable {
    public static let shared = RendererRegistry()

    private var renderers: [any MessageRenderer] = []
    private let lock = NSLock()

    private init() {}

    /// Register a renderer
    public func register(_ renderer: any MessageRenderer) {
        lock.lock()
        defer { lock.unlock() }
        renderers.append(renderer)
    }

    /// Find the best renderer for a message (highest priority that canRender)
    public func renderer(for message: Message) -> any MessageRenderer {
        lock.lock()
        defer { lock.unlock() }
        return renderers
            .sorted { $0.priority > $1.priority }
            .first { $0.canRender(message) }
            ?? PlainTextRenderer()
    }

    /// All registered renderers
    public var all: [any MessageRenderer] {
        lock.lock()
        defer { lock.unlock() }
        return renderers
    }

    /// Reset for testing
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        renderers.removeAll()
    }
}
```

---

## Renderer Implementations

### PlainTextRenderer (priority: 0, fallback)

```swift
// Sources/MessageBridgeClientCore/Renderers/Messages/PlainTextRenderer.swift

public struct PlainTextRenderer: MessageRenderer {
    public let id = "plain-text"
    public let priority = 0

    public init() {}

    public func canRender(_ message: Message) -> Bool {
        true  // Always can render (fallback)
    }

    @MainActor
    public func render(_ message: Message) -> AnyView {
        AnyView(
            Text(message.text ?? "")
                .textSelection(.enabled)
        )
    }
}
```

### LargeEmojiRenderer (priority: 50)

```swift
// Sources/MessageBridgeClientCore/Renderers/Messages/LargeEmojiRenderer.swift

public struct LargeEmojiRenderer: MessageRenderer {
    public let id = "large-emoji"
    public let priority = 50

    public init() {}

    public func canRender(_ message: Message) -> Bool {
        guard let text = message.text, !text.isEmpty else { return false }
        let scalars = text.unicodeScalars
        let isAllEmoji = scalars.allSatisfy { $0.properties.isEmoji && !$0.properties.isASCII }
        let emojiCount = text.count
        return isAllEmoji && emojiCount <= 3
    }

    @MainActor
    public func render(_ message: Message) -> AnyView {
        AnyView(
            Text(message.text ?? "")
                .font(.system(size: 48))
                .textSelection(.enabled)
        )
    }
}
```

### LinkPreviewRenderer (priority: 100)

```swift
// Sources/MessageBridgeClientCore/Renderers/Messages/LinkPreviewRenderer.swift

public struct LinkPreviewRenderer: MessageRenderer {
    public let id = "link-preview"
    public let priority = 100

    public init() {}

    public func canRender(_ message: Message) -> Bool {
        guard let text = message.text else { return false }
        // Check for URL pattern
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range) != nil
    }

    @MainActor
    public func render(_ message: Message) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text ?? "")
                    .textSelection(.enabled)
                // Wraps existing LinkPreviewView which uses LPMetadataProvider
                LinkPreviewView(urlString: extractFirstURL(from: message.text ?? ""))
            }
        )
    }

    private func extractFirstURL(from text: String) -> String {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector?.firstMatch(in: text, range: range),
           let urlRange = Range(match.range, in: text) {
            return String(text[urlRange])
        }
        return ""
    }
}
```

### CodeHighlightRenderer (priority: 100)

```swift
// Sources/MessageBridgeClientCore/Renderers/Messages/CodeHighlightRenderer.swift

public struct CodeHighlightRenderer: MessageRenderer {
    public let id = "code-highlight"
    public let priority = 100

    public init() {}

    public func canRender(_ message: Message) -> Bool {
        guard let codes = message.detectedCodes else { return false }
        return !codes.isEmpty
    }

    @MainActor
    public func render(_ message: Message) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                // Render text with highlighted codes
                Text(highlightedText(message))
                    .textSelection(.enabled)

                // Copy button for first detected code
                if let code = message.detectedCodes?.first {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.value, forType: .string)
                    } label: {
                        Label("Copy \(code.value)", systemImage: "doc.on.doc")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                }
            }
        )
    }

    private func highlightedText(_ message: Message) -> AttributedString {
        var result = AttributedString(message.text ?? "")
        for code in message.detectedCodes ?? [] {
            if let range = result.range(of: code.value) {
                result[range].backgroundColor = .yellow.opacity(0.3)
                result[range].font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            }
        }
        return result
    }
}
```

---

## Client Model Changes

### Message Model Additions

```swift
// Add to existing Message in Models.swift

/// Detected verification codes (from server CodeDetector processor)
var detectedCodes: [DetectedCode]?

/// Text highlights for rendering (codes, links, phone numbers)
var highlights: [TextHighlight]?

/// Link preview metadata (from server or client-side)
var linkPreviews: [LinkPreview]?
```

### New Supporting Models

```swift
// Sources/MessageBridgeClientCore/Models/DetectedCode.swift

public struct DetectedCode: Codable, Sendable, Equatable {
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

// Sources/MessageBridgeClientCore/Models/TextHighlight.swift

public struct TextHighlight: Codable, Sendable, Equatable {
    public let text: String
    public let type: HighlightType

    public enum HighlightType: String, Codable, Sendable {
        case code
        case link
        case phoneNumber
        case email
    }

    public init(text: String, type: HighlightType) {
        self.text = text
        self.type = type
    }
}
```

---

## Integration

### MessageBubble Change

Replace inline text rendering in MessageBubble with:

```swift
// Before (inline in MessageBubble):
Text(message.text ?? "")
    .textSelection(.enabled)

// After (delegated to registry):
let renderer = RendererRegistry.shared.renderer(for: message)
renderer.render(message)
```

Bubble chrome (avatar, timestamp, alignment, background color, tail) remains unchanged in MessageBubble.

### App Registration

```swift
// In ClientApp.swift or AppRegistration.swift

func setupRenderers() {
    RendererRegistry.shared.register(PlainTextRenderer())
    RendererRegistry.shared.register(LargeEmojiRenderer())
    RendererRegistry.shared.register(LinkPreviewRenderer())
    RendererRegistry.shared.register(CodeHighlightRenderer())
}
```

---

## File Structure

**New files:**

```
MessageBridgeClient/Sources/MessageBridgeClientCore/
├── Protocols/
│   └── MessageRenderer.swift
├── Registries/
│   └── RendererRegistry.swift
├── Renderers/
│   └── Messages/
│       ├── PlainTextRenderer.swift
│       ├── LargeEmojiRenderer.swift
│       ├── LinkPreviewRenderer.swift
│       └── CodeHighlightRenderer.swift
└── Models/
    ├── DetectedCode.swift
    └── TextHighlight.swift

Tests/MessageBridgeClientCoreTests/
├── Protocols/
│   └── MessageRendererTests.swift
├── Registries/
│   └── RendererRegistryTests.swift
└── Renderers/
    ├── PlainTextRendererTests.swift
    ├── LargeEmojiRendererTests.swift
    ├── LinkPreviewRendererTests.swift
    └── CodeHighlightRendererTests.swift
```

**Files to modify:**

| File | Change |
|------|--------|
| `Models.swift` | Add detectedCodes, highlights, linkPreviews to Message |
| `MessageThreadView.swift` | Delegate content rendering to RendererRegistry |
| `ClientApp.swift` | Register renderers at startup |
| `CLAUDE.md` | Update migration table (Client Renderers → ✅) |

---

## Future Extensions

**Adding a CodeBlockRenderer:**

```swift
struct CodeBlockRenderer: MessageRenderer {
    let id = "code-block"
    let priority = 75

    func canRender(_ message: Message) -> Bool {
        message.text?.contains("```") == true
    }

    @MainActor
    func render(_ message: Message) -> AnyView {
        // Syntax-highlighted code block
    }
}
```

**Adding RenderContext (v2):**

```swift
protocol RenderContext {
    var isSelected: Bool { get }
    var selectedRange: Range<String.Index>? { get }
    func presentCarousel(_ attachments: [Attachment], startingAt: Int)
    func copyToClipboard(_ text: String)
}
```
