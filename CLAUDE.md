# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Important:** When making changes that affect how users interact with the app (UI, keyboard shortcuts, configuration, installation, etc.), update this document accordingly.

**Required:** At the start of every session, activate the `superpowers:using-superpowers` skill before doing any other work.

---

## Current Focus

> **Update this section at the start and end of each session**

**Active Work:** None - ready for new work

**Last Session:** Pinned Conversations (Bug Fixes & Ship)
- Fixed server crash: `Dictionary(uniqueKeysWithValues:)` trap on duplicate conversation IDs -> switched to `uniquingKeysWith`
- Fixed 1:1 pin matching: added first-name matching for short sidebar names (e.g. "Jamie" -> "Jamie Rodriguez")
- Fixed missing old pinned conversations: cache full `Conversation` objects during matching, inject into API response when outside top-50 fetch window
- Fixed duplicate group detection: participant-set dedup handles protocol-variant chat IDs (SMS/RCS/iMessage for same group)
- Fixed compact mode: temporarily widen Messages.app window to 1400px during sidebar scan when width < 1200px
- Fixed stale unread indicator on injected conversations: force `unreadCount: 0`
- Shipped as PR #1, squash-merged to main
- All 528 server tests + 353 client tests pass

**Known Blockers:** None

**Next Steps:**
1. M4.1 remaining: AppleScript bridge to actually send tapbacks through Messages.app (currently optimistic-only)
2. Start new phase milestones (M4.3 Typing Indicators, M5.5 Search, etc.)
3. Consider adding startIndex/endIndex character offsets to client TextHighlight for precise highlighting

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

## Project Overview

iMessage Bridge is a self-hosted system for accessing iMessages/SMS on a work Mac (without iCloud) by relaying through a home Mac (with iCloud). Two components:

- **MessageBridgeServer** - Swift/Vapor daemon on home Mac, reads from Messages database, exposes REST/WebSocket API
- **MessageBridgeClient** - SwiftUI macOS app on work Mac, connects to server

### Architecture Decisions

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

## How CLAUDE.md and spec.md Work Together

| File        | Purpose      | Contains                                                    |
| ----------- | ------------ | ----------------------------------------------------------- |
| **spec.md** | Requirements | _What_ to build - features, milestones, acceptance criteria |
| **CLAUDE.md** | Architecture | _How_ to build it - patterns, protocols, code guidance    |

**Workflow:** spec.md requirements -> CLAUDE.md extension point -> implement with tests -> verify against spec -> update docs

**Rule: spec.md changes BEFORE code changes** when adding functionality.

> **Architecture Blueprints** for unbuilt features (PresenceProvider, ComposerPlugin implementations, Cache, EventBus, etc.) live in `spec.md` under "Architecture Blueprints". Consult them when starting a new milestone.

---

## Architecture Principles

### 1. Protocol-Driven Design

Every major subsystem defines a protocol. Implementations are interchangeable.

### 2. Registry Pattern

Features self-register at app launch. Adding a feature = creating implementation + one registration line.

### 3. Chain of Responsibility

Messages flow through `ProcessorChain`. Each processor can transform or pass through, run in priority order.

### 4. Configuration

Settings stored via `@AppStorage` and Keychain. A unified Settings system is planned (see spec.md blueprints).

---

## Extension Points

| Want to add...              | Protocol             | Registry                       | Location |
| --------------------------- | -------------------- | ------------------------------ | -------- |
| New tunnel (ZeroTier, etc.) | `TunnelProvider`     | `TunnelRegistry`               | Server   |
| Message transformation      | `MessageProcessor`   | `ProcessorChain`               | Server   |
| Attachment handling          | `AttachmentHandler`  | `AttachmentRegistry`           | Server   |
| Message display style       | `MessageRenderer`    | `RendererRegistry`             | Client   |
| Attachment display          | `AttachmentRenderer` | `AttachmentRendererRegistry`   | Client   |
| Bubble decorations          | `BubbleDecorator`    | `DecoratorRegistry`            | Client   |
| Message actions             | `MessageAction`      | `ActionRegistry`               | Client   |
| Composer features           | `ComposerPlugin`     | `ComposerRegistry`             | Client   |

### Server Protocols (Actual Signatures)

```swift
// TunnelProvider — Actor-based, each tunnel manager implements this
public protocol TunnelProvider: Actor, Identifiable, Sendable {
    nonisolated var id: String { get }
    nonisolated var displayName: String { get }
    nonisolated var description: String { get }
    nonisolated var iconName: String { get }
    var status: TunnelStatus { get async }
    nonisolated func isInstalled() -> Bool
    func connect(port: Int) async throws -> String
    func disconnect() async
    func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void)
}

// MessageProcessor — Transforms ProcessedMessage in priority order
public protocol MessageProcessor: Identifiable, Sendable {
    var id: String { get }
    var priority: Int { get }  // Higher = runs first
    func process(_ message: ProcessedMessage) -> ProcessedMessage
}

// AttachmentHandler — Server-side attachment processing
public protocol AttachmentHandler: Identifiable, Sendable {
    var id: String { get }
    var supportedMimeTypes: [String] { get }
    func generateThumbnail(filePath: String, maxSize: CGSize) async throws -> Data?
    func extractMetadata(filePath: String) async throws -> AttachmentMetadata
}
```

### Client Protocols (Actual Signatures)

```swift
// MessageRenderer — Render message text content
public protocol MessageRenderer: Identifiable, Sendable {
    var id: String { get }
    var priority: Int { get }  // Higher = checked first
    func canRender(_ message: Message) -> Bool
    @MainActor func render(_ message: Message) -> AnyView
}

// AttachmentRenderer — Render message attachments
public protocol AttachmentRenderer: Identifiable, Sendable {
    var id: String { get }
    var priority: Int { get }
    func canRender(_ attachments: [Attachment]) -> Bool
    @MainActor func render(_ attachments: [Attachment]) -> AnyView
}

// BubbleDecorator — Add elements around message bubbles
public protocol BubbleDecorator: Identifiable, Sendable {
    var id: String { get }
    var position: DecoratorPosition { get }  // topLeading, topTrailing, bottomLeading, bottomTrailing, below, overlay
    func shouldDecorate(_ message: Message, context: DecoratorContext) -> Bool
    @MainActor func decorate(_ message: Message, context: DecoratorContext) -> AnyView
}

// MessageAction — Context menu actions on messages
public protocol MessageAction: Identifiable, Sendable {
    var id: String { get }
    var title: String { get }
    var icon: String { get }  // SF Symbol name
    var destructive: Bool { get }
    func isAvailable(for message: Message) -> Bool
    @MainActor func perform(on message: Message) async
}

// ComposerPlugin — Add features to the message compose area
public protocol ComposerPlugin: Identifiable, Sendable {
    var id: String { get }
    var icon: String { get }  // SF Symbol
    var keyboardShortcut: KeyEquivalent? { get }
    var modifiers: EventModifiers { get }
    func showsToolbarButton(context: any ComposerContext) -> Bool
    @MainActor func activate(context: any ComposerContext) async
}
```

### Adding a New Extension

1. Create implementation in the appropriate directory (e.g., `Renderers/Messages/`)
2. Implement the protocol
3. Register in the corresponding registry at app startup
4. Write tests
5. Update this doc if user-facing

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Server status (no auth required) |
| GET | `/conversations` | List conversations (paginated, with pin overlay) |
| GET | `/conversations/:id/messages` | Messages for conversation (paginated) |
| POST | `/conversations/:id/read` | Mark conversation as read |
| GET | `/search` | Search messages by query |
| POST | `/send` | Send text message |
| POST | `/messages/:id/tapback` | Add/remove tapback |
| GET | `/attachments/:id` | Download attachment |
| GET | `/attachments/:id/thumbnail` | Get attachment thumbnail |
| WS | `/ws` | Real-time updates (WebSocket) |

All endpoints except `/health` require `X-API-Key` header. Protected routes use `APIKeyMiddleware` + `E2EMiddleware`.

### WebSocket Message Types

| Type              | Direction | Description                      |
| ----------------- | --------- | -------------------------------- |
| `new_message`     | S->C      | New message received             |
| `message_updated` | S->C      | Message edited or status changed |
| `tapback_added`   | S->C      | Tapback added to message         |
| `tapback_removed` | S->C      | Tapback removed                  |
| `typing`          | C->S      | Client is typing                 |
| `mark_read`       | C->S      | Client read messages             |

---

## Key Models (Actual)

### TapbackType

Values are 2000-based (matching iMessage internal representation):

| Case | Raw Value | Emoji |
|------|-----------|-------|
| love | 2000 | heart |
| like | 2001 | thumbsup |
| dislike | 2002 | thumbsdown |
| laugh | 2003 | laughing face |
| emphasis | 2004 | double exclamation |
| question | 2005 | question mark |
| customEmoji | 2006 | iOS 17+ custom emoji |

Removal types are `rawValue + 1000` (e.g., 3000 removes love).

### Attachment

Uses `guid` (not just `id`), base64 thumbnails (not URLs), has `isSticker` flag. `AttachmentType` enum: `.image`, `.video`, `.audio`, `.document`.

### ProcessedMessage (Server)

Wraps `Message` with processor-added fields: `detectedCodes`, `highlights`, `mentions`, `isEmojiOnly`, `tapbacks`.

---

## Current Implementations

### Server

| Category | Implementations |
|----------|----------------|
| **Tunnel Providers** | `TailscaleManager`, `CloudflaredManager`, `NgrokManager` |
| **Processors** | `CodeDetector`, `EmojiEnlarger`, `MentionExtractor`, `PhoneNumberDetector` |
| **Attachment Handlers** | `ImageHandler`, `VideoHandler` |
| **Other** | `ContactManager`, `PermissionsManager`, `ServerManager` |

### Client

| Category | Implementations |
|----------|----------------|
| **Message Renderers** | `PlainTextRenderer` (priority 0), `HighlightedTextRenderer`, `LinkPreviewRenderer` (100), `LargeEmojiRenderer` (50) |
| **Attachment Renderers** | `SingleImageRenderer`, `ImageGalleryRenderer`, `VideoRenderer`, `AudioRenderer`, `DocumentRenderer` |
| **Bubble Decorators** | `TapbackDecorator` (topTrailing), `ReadReceiptDecorator` (bottomTrailing), `TimestampDecorator` (below) |
| **Message Actions** | `CopyTextAction`, `CopyCodeAction`, `ReplyAction`, `TapbackAction`, `ForwardAction`, `DeleteAction`, `UnsendAction`, `ShareAction`, `TranslateAction` |
| **Composer Plugins** | None yet (protocol exists, no implementations) |

---

## Critical Invariants

### Server
1. **chat.db is NEVER modified** - Read-only mode always
2. **API key required for all endpoints** (except `/health`)
3. **WebSocket broadcasts to ALL connected clients**
4. **Attachments served with proper MIME types**

### Client
1. **Connection state is always accurate** - UI reflects actual connection
2. **Renderers checked in priority order** - Highest priority first
3. **Carousel maintains position** - Swiping doesn't jump

---

## Common Mistakes

### Attachments
- Loading full images instead of thumbnails -> memory explosion
- Blocking main thread on attachment processing -> UI freeze
- Not handling missing thumbnails -> blank spaces

### Tapbacks
- Not deduplicating same user's tapbacks -> shows duplicates
- TapbackType values are 2000-based, NOT 0-based

### Composer
- Blocking send button during attachment upload -> user thinks it's broken
- Losing draft on accidental navigation

### Text Selection & Codes
- Code detection too aggressive -> highlights random numbers
- Code detection too conservative -> misses actual codes

---

## Session Checklist

### Starting a Session
- [ ] Read this CLAUDE.md
- [ ] Check "Current Focus" section
- [ ] Run `swift build` in both projects
- [ ] Run `swift test` in both projects

### Adding a New Feature
- [ ] Update spec.md with requirements first
- [ ] Identify extension point (see table above)
- [ ] Create protocol implementation
- [ ] Register in appropriate registry
- [ ] Write tests
- [ ] Update this doc if user-facing

### Ending a Session
- [ ] Run full test suite
- [ ] Commit work
- [ ] Update "Current Focus" section
