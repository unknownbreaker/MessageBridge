# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Important:** When making changes that affect how users interact with the app (UI, keyboard shortcuts, configuration, installation, etc.), update the User Guide section of this document accordingly.

---

## Current Focus

> **Update this section at the start and end of each session**

**Active Work:** None - ready for new work

**Last Session:** Implemented MessageProcessor chain architecture migration
- Created ProcessedMessage wrapper type and supporting models (DetectedCode, TextHighlight, Mention)
- Created MessageProcessor protocol and ProcessorChain singleton
- Implemented 4 processors: CodeDetector, PhoneNumberDetector, MentionExtractor, EmojiEnlarger
- Integrated ProcessorChain into Routes.swift and WebSocketManager
- Registered processors at server startup
- Updated API response types to use ProcessedMessage

**Known Blockers:** None

**Next Steps:**

1. Implement client-side rendering of ProcessedMessage enrichments
2. Add M5.1 2FA Code Detection milestone tests (verify against spec.md)
3. Continue architecture migration (Attachment Handling next)

---

## How CLAUDE.md and spec.md Work Together

| File          | Purpose      | Contains                                                    |
| ------------- | ------------ | ----------------------------------------------------------- |
| **spec.md**   | Requirements | _What_ to build - features, milestones, acceptance criteria |
| **CLAUDE.md** | Architecture | _How_ to build it - patterns, protocols, code guidance      |

**Workflow for new features:**

```
┌─────────────────────────────────────────────────────────────────┐
│  1. SPEC.MD: Define the feature                                 │
│     - Add milestone with acceptance criteria                    │
│     - Define user stories                                       │
│     - Specify what "done" looks like                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  2. CLAUDE.MD: Find the extension point                         │
│     - Which protocol? (TunnelProvider, MessageRenderer, etc.)   │
│     - Which registry?                                           │
│     - What files to create?                                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  3. IMPLEMENT following CLAUDE.md patterns                      │
│     - Write tests first                                         │
│     - Implement protocol                                        │
│     - Register in registry                                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  4. VERIFY against spec.md acceptance criteria                  │
│     - Does it meet all criteria?                                │
│     - Mark milestone complete                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  5. UPDATE DOCS                                                 │
│     - CLAUDE.md User Guide (if user-facing)                     │
│     - CLAUDE.md extension point docs (if new pattern)           │
│     - spec.md milestone status                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Example:**

To add GIF support:

1. **spec.md** defines:

   ```markdown
   ### Milestone: GIF Support

   **User Stories:**

   - User can search for GIFs in composer
   - User can preview GIF before sending
   - Received GIFs animate in message thread

   **Acceptance Criteria:**

   - [ ] GIF picker accessible from composer toolbar
   - [ ] Search queries Giphy/Tenor API
   - [ ] GIFs display as animated thumbnails
   - [ ] Tapping opens fullscreen animated view
   - [ ] GIFs work in carousel with other images
   ```

2. **CLAUDE.md** tells you:
   - Use `ComposerPlugin` protocol for the picker
   - Use `AttachmentRenderer` for display
   - Register in `ComposerRegistry` and `AttachmentRendererRegistry`
   - Create files in `Composer/` and `Renderers/Attachments/`

**Rule: spec.md changes BEFORE code changes**

When adding functionality:

1. First add/update spec.md with requirements
2. Then write tests based on spec
3. Then implement
4. Then verify against spec criteria

---

## Quick Reference

### Verification Commands (Run Frequently)

```bash
# Full verification - run before commits
cd MessageBridgeServer && swift test && cd ../MessageBridgeClient && swift test

# Server only
cd MessageBridgeServer && swift test

# Client only
cd MessageBridgeClient && swift test

# Build both
cd MessageBridgeServer && swift build && cd ../MessageBridgeClient && swift build
```

---

## Current State vs Target State

> **This section tracks the refactor from original code to new architecture.**

### Architecture Migration Status

| Subsystem               | Current State                                 | Target State                                  | Status             |
| ----------------------- | --------------------------------------------- | --------------------------------------------- | ------------------ |
| **Server Tunnels**      | Separate manager classes, no common interface | `TunnelProvider` protocol + `TunnelRegistry`  | ✅ Migrated        |
| **Server API Routes**   | Standard Vapor routes                         | Same (no change needed)                       | ✅ Already matches |
| **Server Middleware**   | Basic auth middleware                         | Same (no change needed)                       | ✅ Already matches |
| **Message Processing**  | `ProcessorChain` with 4 processors            | `MessageProcessor` chain                      | ✅ Migrated        |
| **Attachment Handling** | Basic serving                                 | `AttachmentHandler` protocol + thumbnails     | ✅ Migrated        |
| **Client Renderers**    | Hardcoded in views                            | `MessageRenderer` protocol + registry         | ✅ Migrated         |
| **Client Attachments**  | Basic/none                                    | `AttachmentRenderer` protocol + carousel      | ✅ Migrated         |
| **Client Decorators**   | Inline in bubble view                         | `BubbleDecorator` protocol                    | ✅ Migrated         |
| **Client Actions**      | Context menu via ActionRegistry               | `MessageAction` protocol + registry           | ✅ Migrated         |
| **Client Composer**     | ComposerPlugin + ExpandingTextEditor          | `ComposerPlugin` protocol + expandable editor | ✅ Migrated         |

### Migration Order

Follow this order to minimize breakage:

```
1. Foundation (no protocol changes, just verify)
   ├── Database layer
   ├── Models
   ├── Security/Encryption
   └── Basic API routes

2. Server Protocols (extract interfaces)
   ├── TunnelProvider + TunnelRegistry
   ├── MessageProcessor + ProcessorChain
   └── AttachmentHandler + AttachmentRegistry

3. Client Protocols (extract interfaces)
   ├── MessageRenderer + RendererRegistry
   ├── AttachmentRenderer + registry
   ├── BubbleDecorator + registry
   ├── MessageAction + registry
   └── ComposerPlugin + registry

4. New Features (implement with new architecture)
   ├── Code detection
   ├── Carousel/gallery
   ├── Tapbacks
   └── etc.
```

### How to Migrate a Subsystem

```
1. Create protocol in Protocols/
2. Create registry in Registries/
3. Make existing code implement protocol
4. Register in app startup
5. Update consumers to use registry
6. Verify tests pass
7. Update this table
```

---

## Milestone Audit Tracker

> **Track progress auditing each spec.md milestone.**

| Milestone                  | Spec Tests Written | Tests Pass | Migrated | Verified |
| -------------------------- | ------------------ | ---------- | -------- | -------- |
| **Phase 1: Core**          |
| M1.1 Basic Server          | ⬜                 | ⬜         | ⬜       | ⬜       |
| M1.2 Basic Client          | ⬜                 | ⬜         | ⬜       | ⬜       |
| M1.3 Send Messages         | ⬜                 | ⬜         | ⬜       | ⬜       |
| M1.4 Real-time Updates     | ⬜                 | ⬜         | ⬜       | ⬜       |
| **Phase 2: Connectivity**  |
| M2.1 Tailscale             | ⬜                 | ⬜         | ⬜       | ⬜       |
| M2.2 Cloudflare            | ⬜                 | ⬜         | ⬜       | ⬜       |
| M2.3 ngrok                 | ⬜                 | ⬜         | ⬜       | ⬜       |
| M2.4 E2E Encryption        | ⬜                 | ⬜         | ⬜       | ⬜       |
| **Phase 3: Rich Messages** |
| M3.1 Attachments Display   | ⬜                 | ⬜         | ⬜       | ⬜       |
| M3.2 Image Gallery         | ⬜                 | ⬜         | ⬜       | ⬜       |
| M3.3 Attachments Send      | ⬜                 | ⬜         | ⬜       | ⬜       |
| M3.4 Audio Messages        | ⬜                 | ⬜         | ⬜       | ⬜       |
| **Phase 4: Reactions**     |
| M4.1 Tapbacks              | ⬜                 | ⬜         | ⬜       | ⬜       |
| M4.2 Read Receipts         | ⬜                 | ⬜         | ⬜       | ⬜       |
| M4.3 Typing Indicators     | ⬜                 | ⬜         | ⬜       | ⬜       |
| **Phase 5: QoL**           |
| M5.1 2FA Code Detection    | ⬜                 | ⬜         | ⬜       | ⬜       |
| M5.2 Multi-line Composer   | ⬜                 | ⬜         | ⬜       | ⬜       |
| M5.3 Text Selection        | ⬜                 | ⬜         | ⬜       | ⬜       |
| M5.4 Link Previews         | ⬜                 | ⬜         | ⬜       | ⬜       |
| M5.5 Search                | ⬜                 | ⬜         | ⬜       | ⬜       |
| **Phase 6: Polish**        |
| M6.1 Contact Names         | ⬜                 | ⬜         | ⬜       | ⬜       |
| M6.2 Notifications         | ⬜                 | ⬜         | ⬜       | ⬜       |
| M6.3 Dark Mode             | ⬜                 | ⬜         | ⬜       | ⬜       |
| M6.4 Keyboard Nav          | ⬜                 | ⬜         | ⬜       | ⬜       |

**Legend:**

- ⬜ Not done
- 🟡 In progress
- ✅ Complete

**Audit process for each milestone:**

1. **Spec Tests Written** - New tests written from spec.md acceptance criteria (without reading implementation)
2. **Tests Pass** - New tests pass against existing code
3. **Migrated** - Code migrated to new architecture (protocols/registries)
4. **Verified** - Final review, mark 🟢 in spec.md

### Extension Points Quick Reference

| Want to add...              | Protocol             | Registry                     | Location |
| --------------------------- | -------------------- | ---------------------------- | -------- |
| New tunnel (ZeroTier, etc.) | `TunnelProvider`     | `TunnelRegistry`             | Server   |
| New API endpoint            | `RouteCollection`    | Vapor routes                 | Server   |
| Message transformation      | `MessageProcessor`   | `ProcessorChain`             | Server   |
| Attachment handling         | `AttachmentHandler`  | `AttachmentRegistry`         | Server   |
| Message display style       | `MessageRenderer`    | `RendererRegistry`           | Client   |
| Attachment display          | `AttachmentRenderer` | `AttachmentRendererRegistry` | Client   |
| Bubble decorations          | `BubbleDecorator`    | `DecoratorRegistry`          | Client   |
| Message actions             | `MessageAction`      | `ActionRegistry`             | Client   |
| Composer features           | `ComposerPlugin`     | `ComposerRegistry`           | Client   |
| Real-time features          | `PresenceProvider`   | `PresenceRegistry`           | Both     |

---

## Project Overview

iMessage Bridge is a self-hosted system for accessing iMessages/SMS on a work Mac (without iCloud) by relaying through a home Mac (with iCloud). Two components:

- **MessageBridgeServer** - Swift/Vapor daemon running on home Mac, reads from Messages database, exposes REST/WebSocket API
- **MessageBridgeClient** - SwiftUI macOS app running on work Mac, connects to server

### Core Capabilities

| Category         | Features                                                  |
| ---------------- | --------------------------------------------------------- |
| **Messages**     | Send/receive text, view conversations, search             |
| **Attachments**  | Images, videos, audio, files with thumbnails and carousel |
| **Reactions**    | Tapbacks (love, like, dislike, laugh, emphasis, question) |
| **Status**       | Typing indicators, read receipts, delivery status         |
| **Connectivity** | Tailscale, Cloudflare Tunnel, ngrok                       |
| **Security**     | E2E encryption (AES-256-GCM), API key auth                |

---

## Architecture Principles

> **These are the TARGET principles for the refactored codebase.**  
> See "Current State vs Target State" above for migration progress.

These principles guide all code in MessageBridge. Follow them when adding new features.

### 1. Protocol-Driven Design

Every major subsystem defines a protocol. Implementations are interchangeable.

```swift
// Protocols live in Protocols/ directory
protocol TunnelProvider { ... }
protocol MessageRenderer { ... }
protocol AttachmentRenderer { ... }
protocol MessageAction { ... }
```

**Why:** New implementations don't require changing existing code. Testing uses mock implementations.

### 2. Registry Pattern

Features self-register at app launch. No hardcoded lists.

```swift
// At app startup
TunnelRegistry.shared.register(TailscaleProvider())
RendererRegistry.shared.register(LinkPreviewRenderer())
ActionRegistry.shared.register(CopyAction())
```

**Why:** Adding a feature = creating implementation + one registration line.

### 3. Chain of Responsibility

Messages flow through processing chains. Each processor can transform or pass through.

```swift
// Server: process outgoing message
let processed = ProcessorChain.shared.process(message)
// Each processor: detect links, generate previews, extract mentions, etc.
```

**Why:** Processing steps are independent and composable.

### 4. Event-Driven Communication

Components communicate via events, not direct references.

```swift
EventBus.shared.emit(.newMessage(message))
EventBus.shared.emit(.typingStarted(conversationId))
EventBus.shared.emit(.messageRead(messageIds))
```

**Why:** Decoupled components. Easy to add new consumers.

### 5. Configuration Schema

All settings follow a consistent pattern.

```swift
enum SettingsKey {
    static let tunnelDefault = "tunnel.default"
    static let e2eEnabled = "security.e2e.enabled"
    static let showTypingIndicators = "ui.typing.enabled"
}
```

---

## Architecture Decisions

| Decision         | Choice              | Rationale                                      |
| ---------------- | ------------------- | ---------------------------------------------- |
| Server framework | Vapor 4             | Mature Swift web framework, native async/await |
| Database access  | GRDB                | Type-safe SQLite, read-only access to chat.db  |
| Client UI        | SwiftUI             | Native macOS, declarative, state management    |
| Real-time        | WebSocket           | Bi-directional, push for messages + presence   |
| Encryption       | AES-256-GCM         | Industry standard, HKDF key derivation         |
| Thread safety    | Swift actors        | Prevents data races                            |
| Extensibility    | Protocol + Registry | New features without modifying existing code   |

---

## Extension Points

> **These protocols define the TARGET architecture.**  
> During refactor, existing code will be migrated to implement these protocols.
> Track migration progress in "Current State vs Target State" section above.

### Server Extensions

#### TunnelProvider

Network tunneling for NAT traversal.

```swift
protocol TunnelProvider: Identifiable, Sendable {
    var id: String { get }
    var displayName: String { get }
    var status: TunnelStatus { get async }
    var publicURL: URL? { get async }
    var requiresE2EEncryption: Bool { get }

    func connect() async throws
    func disconnect() async throws
    func settingsView() -> AnyView
}
```

**Implementations:** `TailscaleProvider`, `CloudflareProvider`, `NgrokProvider`

---

#### MessageProcessor

Transform messages before sending to clients.

```swift
protocol MessageProcessor: Identifiable, Sendable {
    var id: String { get }
    var priority: Int { get }  // Higher = runs first

    /// Process message, return modified version
    func process(_ message: Message) async -> Message
}
```

**Use cases:**

- `LinkUnfurler` - Extract metadata from URLs, generate previews
- `PhoneNumberDetector` - Make phone numbers tappable
- `MentionExtractor` - Parse @mentions
- `EmojiEnlarger` - Make emoji-only messages display larger
- `CodeDetector` - Detect verification codes for quick copy

**CodeDetector (2FA/Verification Codes):**

```swift
struct CodeDetector: MessageProcessor {
    let id = "code-detector"
    let priority = 200  // Run early to detect before other processing

    // Patterns for common verification codes
    let patterns: [CodePattern] = [
        // 4-8 digit codes
        CodePattern(
            regex: #"\b(\d{4,8})\b"#,
            context: [
                "code", "verify", "verification", "confirm", "otp",
                "pin", "password", "passcode", "2fa", "mfa",
                "security", "authentication", "login", "sign in"
            ]
        ),
        // Letter-number codes (like G-123456)
        CodePattern(
            regex: #"\b([A-Z]-?\d{5,8})\b"#,
            context: ["google", "verify", "code"]
        ),
        // Alphanumeric codes (like A1B2C3)
        CodePattern(
            regex: #"\b([A-Z0-9]{6,8})\b"#,
            context: ["code", "verify", "confirmation"]
        )
    ]

    func process(_ message: Message) async -> Message {
        guard let text = message.text else { return message }

        var detectedCodes: [DetectedCode] = []
        let lowercaseText = text.lowercased()

        for pattern in patterns {
            // Check if message has context words suggesting a code
            let hasContext = pattern.context.contains { lowercaseText.contains($0) }
            guard hasContext else { continue }

            // Find matches
            if let regex = try? NSRegularExpression(pattern: pattern.regex),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {

                let code = String(text[range])
                detectedCodes.append(DetectedCode(
                    value: code,
                    range: range,
                    confidence: hasContext ? .high : .medium
                ))
            }
        }

        var modified = message
        modified.detectedCodes = detectedCodes
        modified.highlights.append(contentsOf: detectedCodes.map { code in
            TextHighlight(text: code.value, range: code.range, type: .code)
        })

        return modified
    }
}

struct DetectedCode: Codable, Sendable {
    let value: String
    let range: Range<String.Index>
    let confidence: Confidence

    enum Confidence: String, Codable, Sendable {
        case high    // Context words + code pattern
        case medium  // Code pattern only
        case low     // Might be a code
    }
}

struct CodePattern {
    let regex: String
    let context: [String]
}
```

**Example detections:**

| Message                                     | Detected Code                         |
| ------------------------------------------- | ------------------------------------- |
| "Your verification code is 847293"          | `847293`                              |
| "G-582941 is your Google verification code" | `G-582941`                            |
| "Your Uber code: 8472"                      | `8472`                                |
| "Use code SAVE20 for 20% off"               | Not detected (promotional, not 2FA)   |
| "Call me at 555-1234"                       | Not detected (phone number, not code) |

**Chain execution:**

```swift
// ProcessorChain runs all processors in priority order
var message = originalMessage
for processor in ProcessorChain.shared.sorted {
    message = await processor.process(message)
}
return message
```

---

#### AttachmentHandler

Process attachments server-side.

```swift
protocol AttachmentHandler: Identifiable, Sendable {
    var id: String { get }
    var supportedTypes: [UTType] { get }

    /// Process attachment, return metadata
    func process(_ attachment: Attachment) async throws -> AttachmentMetadata

    /// Generate thumbnail if applicable
    func generateThumbnail(_ attachment: Attachment, size: CGSize) async throws -> Data?
}
```

**Implementations:**

- `ImageHandler` - Dimensions, EXIF, thumbnail generation
- `VideoHandler` - Duration, dimensions, frame extraction, thumbnail
- `AudioHandler` - Duration, waveform generation
- `FileHandler` - File size, icon based on type

**AttachmentMetadata model:**

```swift
struct AttachmentMetadata: Codable, Sendable {
    let type: AttachmentType
    let mimeType: String
    let fileName: String
    let fileSize: Int64
    let dimensions: CGSize?      // Images, videos
    let duration: TimeInterval?  // Audio, video
    let thumbnailURL: URL?
    let waveform: [Float]?       // Audio
    let blurhash: String?        // Placeholder while loading
}
```

---

### Client Extensions

#### MessageRenderer

Render message text content with selectable text.

```swift
protocol MessageRenderer: Identifiable {
    var id: String { get }
    var priority: Int { get }  // Higher = checked first

    /// Can this renderer handle the message?
    func canRender(_ message: Message) -> Bool

    /// Render the message content
    @MainActor func render(_ message: Message, context: RenderContext) -> AnyView
}

protocol RenderContext {
    var isSelected: Bool { get }
    var selectedRange: Range<String.Index>? { get }
    func presentCarousel(_ attachments: [Attachment], startingAt: Int)
    func showTranslation(original: String, translated: String)
    func copyToClipboard(_ text: String)
}
```

**Text Selection in Messages:**

All message renderers support text selection by default:

```swift
struct SelectableMessageText: View {
    let text: String
    let highlights: [TextHighlight]  // Detected codes, links, etc.
    @State private var selectedRange: Range<String.Index>?

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)  // Native macOS text selection
            .contextMenu(forSelectionType: String.self) { selection in
                Button("Copy") {
                    NSPasteboard.general.setString(selection, forType: .string)
                }
                Button("Look Up") {
                    // Dictionary lookup
                }
                if looksLikeCode(selection) {
                    Button("Copy as Code") {
                        NSPasteboard.general.setString(selection.trimmingCharacters(in: .whitespaces), forType: .string)
                    }
                }
            }
    }

    var attributedText: AttributedString {
        var result = AttributedString(text)

        // Apply highlights (codes, links, phone numbers)
        for highlight in highlights {
            if let range = result.range(of: highlight.text) {
                switch highlight.type {
                case .code:
                    result[range].backgroundColor = .yellow.opacity(0.3)
                    result[range].font = .monospacedSystemFont(ofSize: 14, weight: .medium)
                case .link:
                    result[range].foregroundColor = .blue
                    result[range].underlineStyle = .single
                case .phoneNumber:
                    result[range].foregroundColor = .blue
                case .email:
                    result[range].foregroundColor = .blue
                }
            }
        }

        return result
    }
}

struct TextHighlight: Identifiable {
    let id = UUID()
    let text: String
    let range: Range<String.Index>
    let type: HighlightType

    enum HighlightType {
        case code       // Verification codes
        case link       // URLs
        case phoneNumber
        case email
    }
}
```

**PlainTextRenderer with selection:**

```swift
struct PlainTextRenderer: MessageRenderer {
    let id = "plain-text"
    let priority = 0  // Fallback renderer

    func canRender(_ message: Message) -> Bool {
        true  // Always can render
    }

    @MainActor
    func render(_ message: Message, context: RenderContext) -> AnyView {
        AnyView(
            SelectableMessageText(
                text: message.text ?? "",
                highlights: message.detectedHighlights
            )
        )
    }
}
```

**Implementations:**

- `PlainTextRenderer` (priority: 0) - Default fallback
- `LinkPreviewRenderer` (priority: 100) - Rich link cards
- `CodeBlockRenderer` (priority: 100) - Syntax highlighting
- `LargeEmojiRenderer` (priority: 50) - Enlarged emoji-only messages

**Selection logic:**

```swift
func selectRenderer(for message: Message) -> MessageRenderer {
    RendererRegistry.shared.all
        .sorted { $0.priority > $1.priority }
        .first { $0.canRender(message) }
        ?? PlainTextRenderer()
}
```

---

#### AttachmentRenderer

Render message attachments.

```swift
protocol AttachmentRenderer: Identifiable {
    var id: String { get }
    var supportedTypes: [AttachmentType] { get }

    /// Can this renderer handle these attachments?
    func canRender(_ attachments: [Attachment]) -> Bool

    /// Render the attachments
    @MainActor func render(_ attachments: [Attachment], context: RenderContext) -> AnyView
}
```

**Implementations:**

| Renderer               | Handles       | Features                              |
| ---------------------- | ------------- | ------------------------------------- |
| `SingleImageRenderer`  | 1 image       | Thumbnail, tap to fullscreen          |
| `ImageGalleryRenderer` | 2+ images     | Grid layout, carousel on tap          |
| `VideoRenderer`        | Video         | Thumbnail, play button, inline player |
| `AudioRenderer`        | Audio         | Waveform, play/pause, scrubber        |
| `FileRenderer`         | Documents     | Icon, filename, size, tap to download |
| `ContactRenderer`      | Contact cards | Name, photo, add to contacts          |
| `LocationRenderer`     | Location      | Map preview, tap for directions       |

**ImageGalleryRenderer (Carousel) detail:**

```swift
struct ImageGalleryRenderer: AttachmentRenderer {
    let id = "image-gallery"
    let supportedTypes: [AttachmentType] = [.image]

    func canRender(_ attachments: [Attachment]) -> Bool {
        attachments.count >= 2 &&
        attachments.allSatisfy { $0.type == .image }
    }

    @MainActor
    func render(_ attachments: [Attachment], context: RenderContext) -> AnyView {
        AnyView(
            ImageGalleryView(
                attachments: attachments,
                style: attachments.count <= 4 ? .grid : .stack,
                onTap: { index in
                    context.presentCarousel(attachments, startingAt: index)
                }
            )
        )
    }
}
```

**Carousel view:**

```swift
struct CarouselView: View {
    let attachments: [Attachment]
    @State var currentIndex: Int

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                FullscreenMediaView(attachment: attachment)
                    .tag(index)
            }
        }
        .tabViewStyle(.page)
        .overlay(alignment: .bottom) {
            PageIndicator(current: currentIndex, total: attachments.count)
        }
        .gesture(swipeToClose)
    }
}
```

---

#### BubbleDecorator

Add elements around message bubbles.

```swift
protocol BubbleDecorator: Identifiable {
    var id: String { get }
    var position: DecoratorPosition { get }

    /// Should this decorator be shown for this message?
    func shouldDecorate(_ message: Message, context: RenderContext) -> Bool

    /// Render the decoration
    @MainActor func decorate(_ message: Message, context: RenderContext) -> AnyView
}

enum DecoratorPosition {
    case topLeading, topTrailing
    case bottomLeading, bottomTrailing
    case overlay
    case below
}
```

**Implementations:**

| Decorator                 | Position          | Shows                            |
| ------------------------- | ----------------- | -------------------------------- |
| `TapbackDecorator`        | `.topTrailing`    | Reaction bubbles (❤️👍👎😂‼️❓)  |
| `ReadReceiptDecorator`    | `.bottomTrailing` | "Read" / "Delivered" / ✓✓        |
| `TimestampDecorator`      | `.below`          | Time, shown on tap or gap        |
| `DeliveryStatusDecorator` | `.bottomTrailing` | Sending... / Sent / Failed       |
| `ReplyPreviewDecorator`   | `.topLeading`     | Preview of replied-to message    |
| `CodeCopyDecorator`       | `.overlay`        | "Copy Code" button for 2FA codes |

**CodeCopyDecorator (Quick Copy for 2FA):**

```swift
struct CodeCopyDecorator: BubbleDecorator {
    let id = "code-copy"
    let position = DecoratorPosition.overlay

    func shouldDecorate(_ message: Message, context: RenderContext) -> Bool {
        !message.detectedCodes.isEmpty
    }

    @MainActor
    func decorate(_ message: Message, context: RenderContext) -> AnyView {
        AnyView(
            CodeCopyOverlay(codes: message.detectedCodes, context: context)
        )
    }
}

struct CodeCopyOverlay: View {
    let codes: [DetectedCode]
    let context: RenderContext
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        // Position near the code in the message
        VStack {
            Spacer()
            HStack {
                Spacer()

                if codes.count == 1 {
                    // Single code - simple button
                    CopyCodeButton(
                        code: codes[0].value,
                        copied: $copied,
                        onCopy: { copyCode(codes[0].value) }
                    )
                } else {
                    // Multiple codes - menu
                    Menu {
                        ForEach(codes, id: \.value) { code in
                            Button("Copy \(code.value)") {
                                copyCode(code.value)
                            }
                        }
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(8)
        }
        .opacity(hovering || codes.contains { $0.confidence == .high } ? 1 : 0.7)
        .onHover { hovering = $0 }
    }

    func copyCode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        copied = true

        // Show notification
        NotificationCenter.default.post(
            name: .codeCopied,
            object: nil,
            userInfo: ["code": code]
        )

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

struct CopyCodeButton: View {
    let code: String
    @Binding var copied: Bool
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "Copied!" : "Copy \(code)")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(.separator))
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
}
```

**Auto-copy setting (optional):**

For users who want even faster access:

```swift
// Settings
@AppStorage(SettingsKey.autoCopyHighConfidenceCodes)
var autoCopy = false

// In CodeDetector processor
if autoCopy && code.confidence == .high {
    NSPasteboard.general.setString(code.value, forType: .string)

    // Show notification that code was auto-copied
    let notification = UNMutableNotificationContent()
    notification.title = "Code Copied"
    notification.body = "Verification code \(code.value) copied to clipboard"
    notification.sound = .default

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: notification,
        trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
}
```

| Setting          | Key                | Default | Description                     |
| ---------------- | ------------------ | ------- | ------------------------------- |
| Auto-copy codes  | `codes.autoCopy`   | `false` | Auto-copy high-confidence codes |
| Show copy button | `codes.showButton` | `true`  | Show "Copy Code" overlay        |
| Highlight codes  | `codes.highlight`  | `true`  | Yellow highlight on codes       |

**Tapback rendering:**

```swift
struct TapbackDecorator: BubbleDecorator {
    let id = "tapbacks"
    let position = DecoratorPosition.topTrailing

    func shouldDecorate(_ message: Message, context: RenderContext) -> Bool {
        !message.tapbacks.isEmpty
    }

    @MainActor
    func decorate(_ message: Message, context: RenderContext) -> AnyView {
        AnyView(
            TapbackPill(tapbacks: message.tapbacks)
                .offset(x: 8, y: -8)
        )
    }
}

struct TapbackPill: View {
    let tapbacks: [Tapback]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(groupedTapbacks) { group in
                Text(group.emoji)
                if group.count > 1 {
                    Text("\(group.count)")
                        .font(.caption2)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(.regularMaterial))
    }
}
```

---

#### MessageAction

Actions available on messages (context menu, swipe, long-press).

```swift
protocol MessageAction: Identifiable {
    var id: String { get }
    var title: String { get }
    var icon: String { get }  // SF Symbol name
    var destructive: Bool { get }

    /// Is this action available for this message?
    func isAvailable(for message: Message, context: ActionContext) -> Bool

    /// Perform the action
    @MainActor func perform(on message: Message, context: ActionContext) async
}
```

**Implementations:**

| Action            | Icon                       | Destructive | Description                     |
| ----------------- | -------------------------- | ----------- | ------------------------------- |
| `CopyTextAction`  | `doc.on.doc`               | No          | Copy message text               |
| `ReplyAction`     | `arrowshape.turn.up.left`  | No          | Start threaded reply            |
| `TapbackAction`   | `face.smiling`             | No          | Show tapback picker             |
| `ForwardAction`   | `arrowshape.turn.up.right` | No          | Forward to another conversation |
| `DeleteAction`    | `trash`                    | Yes         | Delete message (if own)         |
| `UnsendAction`    | `arrow.uturn.backward`     | Yes         | Unsend (if recent & own)        |
| `ShareAction`     | `square.and.arrow.up`      | No          | System share sheet              |
| `TranslateAction` | `textformat`               | No          | Translate message text          |

**Context menu assembly:**

```swift
func contextMenu(for message: Message) -> some View {
    let actions = ActionRegistry.shared.all
        .filter { $0.isAvailable(for: message, context: context) }

    return ForEach(actions) { action in
        Button(role: action.destructive ? .destructive : nil) {
            Task { await action.perform(on: message, context: context) }
        } label: {
            Label(action.title, systemImage: action.icon)
        }
    }
}
```

---

#### ComposerPlugin

Add features to the message compose area.

```swift
protocol ComposerPlugin: Identifiable {
    var id: String { get }
    var icon: String { get }  // SF Symbol for toolbar
    var keyboardShortcut: KeyboardShortcut? { get }

    /// Toolbar button view (if any)
    @MainActor func toolbarButton(context: ComposerContext) -> AnyView?

    /// Handle activation (toolbar tap or keyboard shortcut)
    @MainActor func activate(context: ComposerContext) async
}

protocol ComposerContext {
    var text: Binding<String> { get }
    var attachments: Binding<[DraftAttachment]> { get }
    func insertText(_ text: String)
    func addAttachment(_ attachment: DraftAttachment)
    func presentSheet(_ view: AnyView)
    func send() async
}
```

**Multi-line Composer:**

The composer supports multi-line input with configurable behavior:

```swift
struct ComposerView: View {
    @Binding var text: String
    @Binding var attachments: [DraftAttachment]
    @AppStorage(SettingsKey.enterToSend) var enterToSend = true
    @AppStorage(SettingsKey.composerMaxLines) var maxLines = 6

    var body: some View {
        VStack(spacing: 0) {
            // Attachment preview strip
            if !attachments.isEmpty {
                AttachmentPreviewStrip(attachments: $attachments)
            }

            HStack(alignment: .bottom) {
                // Plugin toolbar (attachment, photo, etc.)
                ComposerToolbar(context: context)

                // Expandable text editor
                ExpandingTextEditor(
                    text: $text,
                    maxLines: maxLines,
                    placeholder: "Message",
                    onSubmit: handleSubmit
                )

                // Send button
                SendButton(enabled: canSend) {
                    Task { await send() }
                }
            }
        }
    }

    func handleSubmit(event: SubmitEvent) {
        switch (event, enterToSend) {
        case (.enter, true):
            Task { await send() }
        case (.enter, false):
            text += "\n"
        case (.shiftEnter, true):
            text += "\n"
        case (.shiftEnter, false):
            Task { await send() }
        case (.optionEnter, _):
            text += "\n"  // Always newline
        case (.commandEnter, _):
            Task { await send() }  // Always send
        }
    }
}

struct ExpandingTextEditor: View {
    @Binding var text: String
    let maxLines: Int
    let placeholder: String
    let onSubmit: (SubmitEvent) -> Void

    @State private var textHeight: CGFloat = 36

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
            }

            // Actual editor
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 36, maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .onKeyPress(handleKeyPress)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 18).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.separator))
    }

    var maxHeight: CGFloat {
        CGFloat(maxLines) * 20 + 16  // Approximate line height + padding
    }
}
```

**Composer Settings:**

| Setting       | Key                    | Default | Description                          |
| ------------- | ---------------------- | ------- | ------------------------------------ |
| Enter to send | `composer.enterToSend` | `true`  | Enter sends, Shift+Enter for newline |
| Max lines     | `composer.maxLines`    | `6`     | Lines before composer scrolls        |
| Show toolbar  | `composer.showToolbar` | `true`  | Show plugin toolbar                  |

````

**Implementations:**

| Plugin | Icon | Shortcut | Description |
|--------|------|----------|-------------|
| `AttachmentPickerPlugin` | `paperclip` | ⌘⇧A | File picker for any attachment |
| `PhotoPickerPlugin` | `photo` | ⌘⇧P | Photos library picker |
| `CameraPlugin` | `camera` | - | Take photo/video |
| `GifPickerPlugin` | `gift` | ⌘⇧G | GIF search (Giphy/Tenor) |
| `AudioRecorderPlugin` | `mic` | - | Record voice message |
| `EmojiPickerPlugin` | `face.smiling` | ⌘⌃Space | Emoji picker |
| `MentionPlugin` | `at` | @ key | Mention autocomplete |
| `QuickReplyPlugin` | `text.bubble` | - | Suggested quick replies |

**Composer toolbar:**
```swift
struct ComposerToolbar: View {
    let context: ComposerContext

    var body: some View {
        HStack {
            ForEach(ComposerRegistry.shared.all) { plugin in
                if let button = plugin.toolbarButton(context: context) {
                    button
                }
            }
        }
    }
}
````

**AttachmentPickerPlugin detail:**

```swift
struct AttachmentPickerPlugin: ComposerPlugin {
    let id = "attachment-picker"
    let icon = "paperclip"
    let keyboardShortcut = KeyboardShortcut("a", modifiers: [.command, .shift])

    @MainActor
    func toolbarButton(context: ComposerContext) -> AnyView? {
        AnyView(
            Button {
                Task { await activate(context: context) }
            } label: {
                Image(systemName: icon)
            }
            .keyboardShortcut(keyboardShortcut!)
        )
    }

    @MainActor
    func activate(context: ComposerContext) async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                let attachment = DraftAttachment(url: url)
                context.addAttachment(attachment)
            }
        }
    }
}
```

---

#### PresenceProvider

Real-time presence features.

```swift
protocol PresenceProvider: Identifiable, Sendable {
    var id: String { get }

    /// Start observing presence for a conversation
    func observe(conversationId: String) async

    /// Stop observing
    func stopObserving(conversationId: String) async

    /// Current presence state
    var presencePublisher: AnyPublisher<PresenceState, Never> { get }
}

struct PresenceState: Sendable {
    let conversationId: String
    let typingParticipants: [String]  // IDs of people typing
    let lastSeen: [String: Date]      // Last seen times
}
```

**Implementations:**

- `TypingIndicatorProvider` - Shows "..." when others typing
- `OnlineStatusProvider` - Shows last seen / online now

**WebSocket presence messages:**

```json
// Server -> Client: Someone started typing
{
    "type": "typing_started",
    "data": {
        "conversationId": "chat123",
        "participantId": "+15551234567"
    }
}

// Server -> Client: Someone stopped typing
{
    "type": "typing_stopped",
    "data": {
        "conversationId": "chat123",
        "participantId": "+15551234567"
    }
}

// Client -> Server: I'm typing
{
    "type": "typing",
    "data": {
        "conversationId": "chat123"
    }
}
```

---

## Models

### Message (Expanded)

```swift
struct Message: Codable, Identifiable, Sendable {
    let id: Int64
    let conversationId: String
    let text: String?
    let attributedText: AttributedContent?  // Rich text, mentions, links
    let sender: String
    let date: Date
    let isFromMe: Bool

    // Attachments
    let attachments: [Attachment]

    // Reactions
    let tapbacks: [Tapback]

    // Threading
    let replyToMessageId: Int64?
    let threadId: String?

    // Status
    let deliveryStatus: DeliveryStatus
    let readBy: [ReadReceipt]

    // Detected content (populated by MessageProcessors)
    var detectedCodes: [DetectedCode]
    var highlights: [TextHighlight]
    let linkPreviews: [LinkPreview]
    let mentions: [Mention]
}

struct Attachment: Codable, Identifiable, Sendable {
    let id: String
    let type: AttachmentType
    let mimeType: String
    let fileName: String
    let fileSize: Int64
    let url: URL              // Full attachment URL
    let thumbnailURL: URL?    // Thumbnail for images/videos
    let dimensions: CGSize?
    let duration: TimeInterval?
    let blurhash: String?     // Placeholder
    let waveform: [Float]?    // Audio waveform
}

enum AttachmentType: String, Codable, Sendable {
    case image, video, audio, file, contact, location
}

struct Tapback: Codable, Identifiable, Sendable {
    let id: String
    let type: TapbackType
    let sender: String
    let date: Date
}

enum TapbackType: Int, Codable, Sendable {
    case love = 0      // ❤️
    case like = 1      // 👍
    case dislike = 2   // 👎
    case laugh = 3     // 😂
    case emphasis = 4  // ‼️
    case question = 5  // ❓
}

struct LinkPreview: Codable, Sendable {
    let url: URL
    let title: String?
    let description: String?
    let imageURL: URL?
    let siteName: String?
}

enum DeliveryStatus: String, Codable, Sendable {
    case sending, sent, delivered, read, failed
}

struct ReadReceipt: Codable, Sendable {
    let participantId: String
    let readAt: Date
}
```

---

## API Endpoints

| Method | Endpoint                      | Description                      |
| ------ | ----------------------------- | -------------------------------- |
| GET    | `/health`                     | Server status                    |
| GET    | `/conversations`              | List conversations (paginated)   |
| GET    | `/conversations/:id/messages` | Messages for conversation        |
| GET    | `/messages/:id`               | Single message with full details |
| GET    | `/search?q=`                  | Search messages                  |
| POST   | `/send`                       | Send text message                |
| POST   | `/send-attachment`            | Send message with attachments    |
| POST   | `/messages/:id/tapback`       | Add/remove tapback               |
| POST   | `/messages/:id/read`          | Mark as read                     |
| DELETE | `/messages/:id`               | Delete message                   |
| GET    | `/attachments/:id`            | Download attachment              |
| GET    | `/attachments/:id/thumbnail`  | Get attachment thumbnail         |
| WS     | `/ws`                         | Real-time updates                |

All endpoints require `X-API-Key` header.

### WebSocket Message Types

| Type              | Direction | Description                      |
| ----------------- | --------- | -------------------------------- |
| `new_message`     | S→C       | New message received             |
| `message_updated` | S→C       | Message edited or status changed |
| `message_deleted` | S→C       | Message deleted                  |
| `tapback_added`   | S→C       | Tapback added to message         |
| `tapback_removed` | S→C       | Tapback removed                  |
| `typing_started`  | S→C       | Participant started typing       |
| `typing_stopped`  | S→C       | Participant stopped typing       |
| `read_receipt`    | S→C       | Message marked as read           |
| `typing`          | C→S       | Client is typing                 |
| `mark_read`       | C→S       | Client read messages             |

---

## Adding New Features

### Adding an Attachment Renderer

**Example: Adding a Location Renderer**

1. Create `Sources/MessageBridgeClientCore/Renderers/Attachments/LocationRenderer.swift`:

```swift
struct LocationRenderer: AttachmentRenderer {
    let id = "location"
    let supportedTypes: [AttachmentType] = [.location]

    func canRender(_ attachments: [Attachment]) -> Bool {
        attachments.count == 1 && attachments[0].type == .location
    }

    @MainActor
    func render(_ attachments: [Attachment], context: RenderContext) -> AnyView {
        guard let location = attachments.first else {
            return AnyView(EmptyView())
        }

        return AnyView(
            LocationPreviewView(
                coordinate: location.coordinate,
                onTap: {
                    // Open in Maps
                    let url = URL(string: "maps://?ll=\(location.lat),\(location.lon)")!
                    NSWorkspace.shared.open(url)
                }
            )
        )
    }
}
```

2. Register in `ClientApp.swift`:

```swift
AttachmentRendererRegistry.shared.register(LocationRenderer())
```

3. Write tests in `Tests/MessageBridgeClientCoreTests/Renderers/LocationRendererTests.swift`

---

### Adding a Message Action

**Example: Adding Translation**

1. Create `Sources/MessageBridgeClientCore/Actions/TranslateAction.swift`:

```swift
struct TranslateAction: MessageAction {
    let id = "translate"
    let title = "Translate"
    let icon = "textformat"
    let destructive = false

    func isAvailable(for message: Message, context: ActionContext) -> Bool {
        message.text != nil && !message.text!.isEmpty
    }

    @MainActor
    func perform(on message: Message, context: ActionContext) async {
        guard let text = message.text else { return }

        // Use system translation
        let config = TranslationSession.Configuration(
            source: nil,  // Auto-detect
            target: Locale.current.language
        )

        do {
            let session = try await TranslationSession(configuration: config)
            let result = try await session.translate(text)
            context.showTranslation(original: text, translated: result.targetText)
        } catch {
            context.showError("Translation failed")
        }
    }
}
```

2. Register in `ClientApp.swift`:

```swift
ActionRegistry.shared.register(TranslateAction())
```

---

### Adding a Composer Plugin

**Example: Adding Voice Messages**

1. Create `Sources/MessageBridgeClientCore/Composer/AudioRecorderPlugin.swift`:

```swift
struct AudioRecorderPlugin: ComposerPlugin {
    let id = "audio-recorder"
    let icon = "mic"
    let keyboardShortcut: KeyboardShortcut? = nil

    @MainActor
    func toolbarButton(context: ComposerContext) -> AnyView? {
        AnyView(
            AudioRecordButton(context: context)
        )
    }

    @MainActor
    func activate(context: ComposerContext) async {
        // Handled by AudioRecordButton's internal state
    }
}

struct AudioRecordButton: View {
    let context: ComposerContext
    @StateObject private var recorder = AudioRecorder()

    var body: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
                if let url = recorder.recordingURL {
                    let attachment = DraftAttachment(url: url, type: .audio)
                    context.addAttachment(attachment)
                }
            } else {
                recorder.start()
            }
        } label: {
            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic")
                .foregroundStyle(recorder.isRecording ? .red : .primary)
        }
    }
}
```

2. Register in `ClientApp.swift`:

```swift
ComposerRegistry.shared.register(AudioRecorderPlugin())
```

---

## Critical Invariants

**These must ALWAYS be true.**

### Server

1. **chat.db is NEVER modified** - Read-only mode always
2. **API key required for all endpoints** - No unauthenticated access
3. **WebSocket broadcasts to ALL connected clients** - No message loss
4. **Attachments served with proper MIME types** - Browser compatibility
5. **Thumbnails generated on-demand and cached** - Don't block on startup

### Client

1. **Connection state is always accurate** - UI reflects actual connection
2. **Renderers checked in priority order** - Highest priority first
3. **Attachment downloads are resumable** - Don't re-download on reconnect
4. **Carousel maintains position** - Swiping doesn't jump
5. **Draft attachments persist until sent** - Don't lose on app switch

---

## Common Mistakes

### Attachments

- ❌ **Loading full images instead of thumbnails** → Memory explosion
- ❌ **Blocking main thread on attachment processing** → UI freeze
- ❌ **Not handling missing thumbnails** → Blank spaces
- ❌ **Assuming attachment URL is always reachable** → Crashes

### Carousel/Gallery

- ❌ **Loading all images at once** → Memory issues with many photos
- ❌ **Not preloading adjacent images** → Visible loading on swipe
- ❌ **Losing zoom state on page change** → Frustrating UX

### Tapbacks

- ❌ **Not deduplicating same user's tapbacks** → Shows duplicates
- ❌ **Animating every tapback update** → Jittery UI

### Composer

- ❌ **Blocking send button during attachment upload** → User thinks it's broken
- ❌ **Losing draft on accidental navigation** → Frustration
- ❌ **Not compressing images before send** → Slow uploads
- ❌ **Enter always sends with no option** → Can't write multi-line messages
- ❌ **Text field doesn't expand** → Can't see what you're writing

### Text Selection & Codes

- ❌ **Text not selectable in messages** → Can't copy portions
- ❌ **Code detection too aggressive** → Highlights random numbers
- ❌ **Code detection too conservative** → Misses actual codes
- ❌ **Copy button covers message text** → Blocks reading
- ❌ **Auto-copy without notification** → User doesn't know it happened

---

## File Structure

```
MessageBridge/
├── CLAUDE.md
├── spec.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── BUGS_AND_ISSUES.md
│
├── .claude/
│   ├── commands/
│   │   ├── commit-push-pr.md
│   │   ├── test-verify.md
│   │   ├── simplify.md
│   │   └── plan-feature.md
│   ├── agents/
│   │   ├── swift-reviewer.md
│   │   ├── test-adversary.md
│   │   └── vapor-expert.md
│   ├── settings.json
│   └── plans/
│       └── .gitkeep
│
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── release.yml
│
├── MessageBridgeServer/
│   ├── VERSION
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeCore/
│   │   │   │
│   │   │   ├── Protocols/
│   │   │   │   ├── TunnelProvider.swift
│   │   │   │   ├── MessageProcessor.swift
│   │   │   │   ├── AttachmentHandler.swift
│   │   │   │   ├── AuthProvider.swift
│   │   │   │   └── EventHandler.swift
│   │   │   │
│   │   │   ├── Registries/
│   │   │   │   ├── TunnelRegistry.swift
│   │   │   │   ├── ProcessorChain.swift
│   │   │   │   ├── AttachmentRegistry.swift
│   │   │   │   ├── AuthRegistry.swift
│   │   │   │   └── RegistryProtocol.swift
│   │   │   │
│   │   │   ├── Events/
│   │   │   │   ├── EventBus.swift
│   │   │   │   ├── AppEvent.swift
│   │   │   │   └── Handlers/
│   │   │   │       ├── WebSocketBroadcaster.swift
│   │   │   │       └── LoggingHandler.swift
│   │   │   │
│   │   │   ├── Models/
│   │   │   │   ├── Message.swift
│   │   │   │   ├── Conversation.swift
│   │   │   │   ├── Attachment.swift
│   │   │   │   ├── AttachmentMetadata.swift
│   │   │   │   ├── Tapback.swift
│   │   │   │   ├── DetectedCode.swift
│   │   │   │   ├── TextHighlight.swift
│   │   │   │   ├── LinkPreview.swift
│   │   │   │   ├── ReadReceipt.swift
│   │   │   │   ├── DeliveryStatus.swift
│   │   │   │   ├── PresenceState.swift
│   │   │   │   ├── WebSocketMessage.swift
│   │   │   │   └── APIError.swift
│   │   │   │
│   │   │   ├── Database/
│   │   │   │   ├── ChatDatabase.swift
│   │   │   │   ├── MessageQueries.swift
│   │   │   │   ├── ConversationQueries.swift
│   │   │   │   ├── AttachmentQueries.swift
│   │   │   │   ├── DatabaseMigrations.swift
│   │   │   │   └── AppleTimestamp.swift
│   │   │   │
│   │   │   ├── API/
│   │   │   │   ├── Middleware/
│   │   │   │   │   ├── APIKeyAuthMiddleware.swift
│   │   │   │   │   ├── LoggingMiddleware.swift
│   │   │   │   │   ├── RateLimitMiddleware.swift
│   │   │   │   │   └── E2EEncryptionMiddleware.swift
│   │   │   │   │
│   │   │   │   └── Routes/
│   │   │   │       ├── HealthRoutes.swift
│   │   │   │       ├── ConversationRoutes.swift
│   │   │   │       ├── MessageRoutes.swift
│   │   │   │       ├── AttachmentRoutes.swift
│   │   │   │       ├── SearchRoutes.swift
│   │   │   │       ├── TapbackRoutes.swift
│   │   │   │       └── WebSocketRoutes.swift
│   │   │   │
│   │   │   ├── Processors/
│   │   │   │   ├── LinkUnfurler.swift
│   │   │   │   ├── CodeDetector.swift
│   │   │   │   ├── PhoneNumberDetector.swift
│   │   │   │   ├── EmailDetector.swift
│   │   │   │   ├── MentionExtractor.swift
│   │   │   │   └── EmojiEnlarger.swift
│   │   │   │
│   │   │   ├── Attachments/
│   │   │   │   ├── ImageHandler.swift
│   │   │   │   ├── VideoHandler.swift
│   │   │   │   ├── AudioHandler.swift
│   │   │   │   ├── FileHandler.swift
│   │   │   │   ├── ContactHandler.swift
│   │   │   │   ├── LocationHandler.swift
│   │   │   │   ├── ThumbnailGenerator.swift
│   │   │   │   ├── ThumbnailCache.swift
│   │   │   │   ├── WaveformGenerator.swift
│   │   │   │   └── BlurhashGenerator.swift
│   │   │   │
│   │   │   ├── Tunnels/
│   │   │   │   ├── TunnelStatus.swift
│   │   │   │   ├── TunnelSettings.swift
│   │   │   │   ├── TunnelError.swift
│   │   │   │   ├── Tailscale/
│   │   │   │   │   ├── TailscaleProvider.swift
│   │   │   │   │   ├── TailscaleConfig.swift
│   │   │   │   │   └── TailscaleIPDetector.swift
│   │   │   │   ├── Cloudflare/
│   │   │   │   │   ├── CloudflareProvider.swift
│   │   │   │   │   ├── CloudflareConfig.swift
│   │   │   │   │   └── CloudflaredProcess.swift
│   │   │   │   └── Ngrok/
│   │   │   │       ├── NgrokProvider.swift
│   │   │   │       ├── NgrokConfig.swift
│   │   │   │       └── NgrokProcess.swift
│   │   │   │
│   │   │   ├── Messaging/
│   │   │   │   ├── AppleScriptSender.swift
│   │   │   │   ├── MessageSendRequest.swift
│   │   │   │   └── MessageSendResult.swift
│   │   │   │
│   │   │   ├── FileWatcher/
│   │   │   │   ├── ChatDatabaseWatcher.swift
│   │   │   │   └── FSEventsWrapper.swift
│   │   │   │
│   │   │   ├── Security/
│   │   │   │   ├── KeychainManager.swift
│   │   │   │   ├── APIKeyGenerator.swift
│   │   │   │   ├── E2EEncryption.swift
│   │   │   │   ├── AESCipher.swift
│   │   │   │   └── HKDFKeyDerivation.swift
│   │   │   │
│   │   │   ├── Settings/
│   │   │   │   ├── SettingsKey.swift
│   │   │   │   ├── Settings.swift
│   │   │   │   └── SettingsMigration.swift
│   │   │   │
│   │   │   ├── Presence/
│   │   │   │   ├── TypingTracker.swift
│   │   │   │   ├── TypingTimeout.swift
│   │   │   │   └── PresenceBroadcaster.swift
│   │   │   │
│   │   │   ├── Logging/
│   │   │   │   ├── Logger.swift
│   │   │   │   ├── LogLevel.swift
│   │   │   │   ├── LogEntry.swift
│   │   │   │   ├── FileLogHandler.swift
│   │   │   │   └── LogRotation.swift
│   │   │   │
│   │   │   └── Version/
│   │   │       └── Version.swift
│   │   │
│   │   └── MessageBridgeServer/
│   │       ├── App/
│   │       │   ├── ServerApp.swift
│   │       │   ├── AppDelegate.swift
│   │       │   └── configure.swift
│   │       │
│   │       └── Views/
│   │           ├── MenuBarView.swift
│   │           ├── StatusMenuView.swift
│   │           ├── Settings/
│   │           │   ├── SettingsView.swift
│   │           │   ├── GeneralSettingsView.swift
│   │           │   ├── SecuritySettingsView.swift
│   │           │   ├── TailscaleSettingsView.swift
│   │           │   ├── CloudflareSettingsView.swift
│   │           │   └── NgrokSettingsView.swift
│   │           ├── LogViewerView.swift
│   │           └── OnboardingView.swift
│   │
│   └── Tests/
│       └── MessageBridgeCoreTests/
│           ├── Database/
│           │   ├── ChatDatabaseTests.swift
│           │   ├── MessageQueriesTests.swift
│           │   └── AppleTimestampTests.swift
│           ├── Processors/
│           │   ├── CodeDetectorTests.swift
│           │   ├── LinkUnfurlerTests.swift
│           │   └── PhoneNumberDetectorTests.swift
│           ├── Attachments/
│           │   ├── ImageHandlerTests.swift
│           │   ├── VideoHandlerTests.swift
│           │   └── ThumbnailGeneratorTests.swift
│           ├── Tunnels/
│           │   ├── TailscaleProviderTests.swift
│           │   ├── CloudflareProviderTests.swift
│           │   └── NgrokProviderTests.swift
│           ├── API/
│           │   ├── ConversationRoutesTests.swift
│           │   ├── MessageRoutesTests.swift
│           │   ├── AttachmentRoutesTests.swift
│           │   └── WebSocketRoutesTests.swift
│           ├── Security/
│           │   ├── E2EEncryptionTests.swift
│           │   └── APIKeyGeneratorTests.swift
│           └── Mocks/
│               ├── MockChatDatabase.swift
│               ├── MockTunnelProvider.swift
│               └── MockEventBus.swift
│
├── MessageBridgeClient/
│   ├── VERSION
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MessageBridgeClientCore/
│   │   │   │
│   │   │   ├── Protocols/
│   │   │   │   ├── MessageRenderer.swift
│   │   │   │   ├── AttachmentRenderer.swift
│   │   │   │   ├── BubbleDecorator.swift
│   │   │   │   ├── MessageAction.swift
│   │   │   │   ├── ComposerPlugin.swift
│   │   │   │   ├── PresenceProvider.swift
│   │   │   │   └── RenderContext.swift
│   │   │   │
│   │   │   ├── Registries/
│   │   │   │   ├── RendererRegistry.swift
│   │   │   │   ├── AttachmentRendererRegistry.swift
│   │   │   │   ├── DecoratorRegistry.swift
│   │   │   │   ├── ActionRegistry.swift
│   │   │   │   ├── ComposerRegistry.swift
│   │   │   │   └── PresenceRegistry.swift
│   │   │   │
│   │   │   ├── Events/
│   │   │   │   ├── EventBus.swift
│   │   │   │   ├── ClientEvent.swift
│   │   │   │   └── Handlers/
│   │   │   │       ├── NotificationHandler.swift
│   │   │   │       └── BadgeUpdateHandler.swift
│   │   │   │
│   │   │   ├── Models/
│   │   │   │   ├── Message.swift
│   │   │   │   ├── Conversation.swift
│   │   │   │   ├── Attachment.swift
│   │   │   │   ├── DraftAttachment.swift
│   │   │   │   ├── DraftMessage.swift
│   │   │   │   ├── Tapback.swift
│   │   │   │   ├── DetectedCode.swift
│   │   │   │   ├── TextHighlight.swift
│   │   │   │   ├── LinkPreview.swift
│   │   │   │   ├── ConnectionStatus.swift
│   │   │   │   └── PresenceState.swift
│   │   │   │
│   │   │   ├── Services/
│   │   │   │   ├── BridgeConnection.swift
│   │   │   │   ├── WebSocketClient.swift
│   │   │   │   ├── RESTClient.swift
│   │   │   │   ├── AttachmentDownloader.swift
│   │   │   │   ├── AttachmentUploader.swift
│   │   │   │   ├── ImageCompressor.swift
│   │   │   │   ├── ContactResolver.swift
│   │   │   │   └── NotificationService.swift
│   │   │   │
│   │   │   ├── ViewModels/
│   │   │   │   ├── MessagesViewModel.swift
│   │   │   │   ├── ConversationListViewModel.swift
│   │   │   │   ├── MessageThreadViewModel.swift
│   │   │   │   ├── ComposerViewModel.swift
│   │   │   │   ├── SettingsViewModel.swift
│   │   │   │   └── ConnectionViewModel.swift
│   │   │   │
│   │   │   ├── Renderers/
│   │   │   │   ├── Messages/
│   │   │   │   │   ├── PlainTextRenderer.swift
│   │   │   │   │   ├── SelectableMessageText.swift
│   │   │   │   │   ├── LinkPreviewRenderer.swift
│   │   │   │   │   ├── CodeBlockRenderer.swift
│   │   │   │   │   └── LargeEmojiRenderer.swift
│   │   │   │   │
│   │   │   │   └── Attachments/
│   │   │   │       ├── SingleImageRenderer.swift
│   │   │   │       ├── ImageGalleryRenderer.swift
│   │   │   │       ├── VideoRenderer.swift
│   │   │   │       ├── AudioRenderer.swift
│   │   │   │       ├── FileRenderer.swift
│   │   │   │       ├── ContactRenderer.swift
│   │   │   │       └── LocationRenderer.swift
│   │   │   │
│   │   │   ├── Decorators/
│   │   │   │   ├── TapbackDecorator.swift
│   │   │   │   ├── TapbackPill.swift
│   │   │   │   ├── ReadReceiptDecorator.swift
│   │   │   │   ├── DeliveryStatusDecorator.swift
│   │   │   │   ├── TimestampDecorator.swift
│   │   │   │   ├── ReplyPreviewDecorator.swift
│   │   │   │   ├── CodeCopyDecorator.swift
│   │   │   │   └── CopyCodeButton.swift
│   │   │   │
│   │   │   ├── Actions/
│   │   │   │   ├── CopyTextAction.swift
│   │   │   │   ├── ReplyAction.swift
│   │   │   │   ├── TapbackAction.swift
│   │   │   │   ├── ForwardAction.swift
│   │   │   │   ├── DeleteAction.swift
│   │   │   │   ├── UnsendAction.swift
│   │   │   │   ├── ShareAction.swift
│   │   │   │   └── TranslateAction.swift
│   │   │   │
│   │   │   ├── Composer/
│   │   │   │   ├── ComposerContext.swift
│   │   │   │   ├── AttachmentPickerPlugin.swift
│   │   │   │   ├── PhotoPickerPlugin.swift
│   │   │   │   ├── CameraPlugin.swift
│   │   │   │   ├── GifPickerPlugin.swift
│   │   │   │   ├── AudioRecorderPlugin.swift
│   │   │   │   ├── AudioRecorder.swift
│   │   │   │   ├── EmojiPickerPlugin.swift
│   │   │   │   └── MentionPlugin.swift
│   │   │   │
│   │   │   ├── Presence/
│   │   │   │   ├── TypingIndicatorProvider.swift
│   │   │   │   ├── TypingIndicatorView.swift
│   │   │   │   └── OnlineStatusProvider.swift
│   │   │   │
│   │   │   ├── Security/
│   │   │   │   ├── KeychainManager.swift
│   │   │   │   ├── E2EEncryption.swift
│   │   │   │   ├── AESCipher.swift
│   │   │   │   └── HKDFKeyDerivation.swift
│   │   │   │
│   │   │   ├── Settings/
│   │   │   │   ├── SettingsKey.swift
│   │   │   │   ├── Settings.swift
│   │   │   │   └── SettingsMigration.swift
│   │   │   │
│   │   │   ├── Logging/
│   │   │   │   ├── Logger.swift
│   │   │   │   ├── LogLevel.swift
│   │   │   │   ├── LogEntry.swift
│   │   │   │   ├── FileLogHandler.swift
│   │   │   │   └── LogRotation.swift
│   │   │   │
│   │   │   ├── Cache/
│   │   │   │   ├── ImageCache.swift
│   │   │   │   ├── ThumbnailCache.swift
│   │   │   │   ├── DiskCache.swift
│   │   │   │   └── CachePolicy.swift
│   │   │   │
│   │   │   └── Version/
│   │   │       └── Version.swift
│   │   │
│   │   └── MessageBridgeClient/
│   │       ├── App/
│   │       │   ├── ClientApp.swift
│   │       │   ├── AppDelegate.swift
│   │       │   └── AppRegistration.swift
│   │       │
│   │       └── Views/
│   │           ├── ContentView.swift
│   │           ├── Conversations/
│   │           │   ├── ConversationListView.swift
│   │           │   ├── ConversationRow.swift
│   │           │   ├── ConversationAvatar.swift
│   │           │   └── SearchBar.swift
│   │           │
│   │           ├── Messages/
│   │           │   ├── MessageThreadView.swift
│   │           │   ├── MessageList.swift
│   │           │   ├── MessageBubble.swift
│   │           │   ├── MessageBubbleContent.swift
│   │           │   ├── MessageContextMenu.swift
│   │           │   └── DateSeparator.swift
│   │           │
│   │           ├── Attachments/
│   │           │   ├── AttachmentPreviewStrip.swift
│   │           │   ├── AttachmentThumbnail.swift
│   │           │   ├── ImageGridView.swift
│   │           │   ├── AudioPlayerView.swift
│   │           │   ├── VideoPlayerView.swift
│   │           │   └── FileIconView.swift
│   │           │
│   │           ├── Carousel/
│   │           │   ├── CarouselView.swift
│   │           │   ├── FullscreenMediaView.swift
│   │           │   ├── FullscreenImageView.swift
│   │           │   ├── FullscreenVideoView.swift
│   │           │   ├── PageIndicator.swift
│   │           │   └── ZoomableImageView.swift
│   │           │
│   │           ├── Composer/
│   │           │   ├── ComposerView.swift
│   │           │   ├── ExpandingTextEditor.swift
│   │           │   ├── ComposerToolbar.swift
│   │           │   ├── SendButton.swift
│   │           │   ├── DraftAttachmentPreview.swift
│   │           │   └── ReplyPreviewBar.swift
│   │           │
│   │           ├── Tapbacks/
│   │           │   ├── TapbackPicker.swift
│   │           │   └── TapbackButton.swift
│   │           │
│   │           ├── Settings/
│   │           │   ├── SettingsView.swift
│   │           │   ├── GeneralSettingsView.swift
│   │           │   ├── ConnectionSettingsView.swift
│   │           │   ├── SecuritySettingsView.swift
│   │           │   ├── ComposerSettingsView.swift
│   │           │   ├── NotificationSettingsView.swift
│   │           │   └── AppearanceSettingsView.swift
│   │           │
│   │           ├── Status/
│   │           │   ├── ConnectionStatusView.swift
│   │           │   └── ConnectionStatusIndicator.swift
│   │           │
│   │           ├── Logs/
│   │           │   ├── LogViewerView.swift
│   │           │   ├── LogEntryRow.swift
│   │           │   └── LogFilterBar.swift
│   │           │
│   │           └── Shared/
│   │               ├── LoadingView.swift
│   │               ├── ErrorView.swift
│   │               ├── EmptyStateView.swift
│   │               └── ToastView.swift
│   │
│   └── Tests/
│       └── MessageBridgeClientCoreTests/
│           ├── Renderers/
│           │   ├── PlainTextRendererTests.swift
│           │   ├── LinkPreviewRendererTests.swift
│           │   ├── ImageGalleryRendererTests.swift
│           │   └── VideoRendererTests.swift
│           ├── Decorators/
│           │   ├── TapbackDecoratorTests.swift
│           │   ├── CodeCopyDecoratorTests.swift
│           │   └── ReadReceiptDecoratorTests.swift
│           ├── Actions/
│           │   ├── CopyTextActionTests.swift
│           │   ├── ReplyActionTests.swift
│           │   └── TapbackActionTests.swift
│           ├── Composer/
│           │   ├── ExpandingTextEditorTests.swift
│           │   └── AttachmentPickerPluginTests.swift
│           ├── Services/
│           │   ├── BridgeConnectionTests.swift
│           │   ├── WebSocketClientTests.swift
│           │   └── AttachmentDownloaderTests.swift
│           ├── ViewModels/
│           │   ├── MessagesViewModelTests.swift
│           │   ├── ComposerViewModelTests.swift
│           │   └── ConversationListViewModelTests.swift
│           ├── Security/
│           │   └── E2EEncryptionTests.swift
│           └── Mocks/
│               ├── MockBridgeConnection.swift
│               ├── MockRenderer.swift
│               └── MockComposerContext.swift
│
└── Scripts/
    ├── build-release.sh
    ├── create-dmgs.sh
    ├── generate-changelog.sh
    ├── install-server.sh
    ├── package-client.sh
    ├── run-tests.sh
    ├── lint.sh
    ├── setup-tailscale.md
    ├── setup-cloudflare-tunnel.md
    └── setup-ngrok.md
```

---

## Session Checklist

### Starting a Session

- [ ] Read this CLAUDE.md fully
- [ ] Check "Current Focus" section
- [ ] Run `swift build` in both projects
- [ ] Run `swift test` in both projects

### Adding a New Feature

- [ ] Identify the extension point (see table at top)
- [ ] Create protocol implementation
- [ ] Register in appropriate registry
- [ ] Write tests (see existing implementations for patterns)
- [ ] Update CLAUDE.md if user-facing

### Ending a Session

- [ ] Run full test suite
- [ ] Commit work
- [ ] Update "Current Focus" section
