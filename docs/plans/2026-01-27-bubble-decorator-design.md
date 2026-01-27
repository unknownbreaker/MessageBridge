# BubbleDecorator Protocol Design

**Date:** 2026-01-27
**Status:** Approved
**Goal:** Extract bubble decorations (timestamp, future tapbacks/read receipts) from MessageBubble into a protocol-based architecture with positional slots.

---

## Problem

MessageBubble has timestamp rendering hardcoded inline. Future decorations (tapbacks, read receipts, delivery status, code-copy overlay) would each require modifying MessageBubble directly. No way to add decorations without touching core bubble code.

## Design Goals

1. **Positional** — Decorators declare where they appear (top, bottom, below, overlay)
2. **Composable** — Multiple decorators can coexist at different positions
3. **Conditional** — Each decorator decides whether to show for a given message
4. **Consistent** — Same protocol + registry pattern as MessageRenderer and AttachmentRenderer

## Scope

**In scope (v1):**
- BubbleDecorator protocol with DecoratorPosition
- DecoratorRegistry singleton
- TimestampDecorator (extracts existing timestamp)
- MessageBubble integration with positional rendering

**Out of scope (future):**
- TapbackDecorator (needs tapback model fields)
- ReadReceiptDecorator (needs read receipt model)
- DeliveryStatusDecorator (needs delivery status model)
- CodeCopyDecorator (can add when CodeDetector ships)
- ReplyPreviewDecorator (needs threading model)

---

## Core Types

### DecoratorPosition

```swift
// Sources/MessageBridgeClientCore/Protocols/BubbleDecorator.swift

public enum DecoratorPosition: String, Codable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case below
    case overlay
}
```

### BubbleDecorator Protocol

```swift
public protocol BubbleDecorator: Identifiable, Sendable {
    /// Unique identifier for this decorator
    var id: String { get }

    /// Where this decorator appears relative to the bubble
    var position: DecoratorPosition { get }

    /// Whether this decorator should show for the given message
    func shouldDecorate(_ message: Message) -> Bool

    /// Render the decoration
    @MainActor func decorate(_ message: Message) -> AnyView
}
```

### DecoratorRegistry

```swift
// Sources/MessageBridgeClientCore/Registries/DecoratorRegistry.swift

public final class DecoratorRegistry: @unchecked Sendable {
    public static let shared = DecoratorRegistry()

    private var decorators: [any BubbleDecorator] = []
    private let lock = NSLock()

    private init() {}

    public func register(_ decorator: any BubbleDecorator) {
        lock.lock()
        defer { lock.unlock() }
        decorators.append(decorator)
    }

    /// Get all decorators that should show for this message at the given position
    public func decorators(for message: Message, at position: DecoratorPosition) -> [any BubbleDecorator] {
        lock.lock()
        defer { lock.unlock() }
        return decorators
            .filter { $0.position == position && $0.shouldDecorate(message) }
    }

    /// All registered decorators
    public var all: [any BubbleDecorator] {
        lock.lock()
        defer { lock.unlock() }
        return decorators
    }

    /// Reset for testing
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        decorators.removeAll()
    }
}
```

---

## Decorator Implementation

### TimestampDecorator

```swift
// Sources/MessageBridgeClientCore/Decorators/TimestampDecorator.swift

public struct TimestampDecorator: BubbleDecorator {
    public let id = "timestamp"
    public let position = DecoratorPosition.below

    public init() {}

    public func shouldDecorate(_ message: Message) -> Bool {
        true  // Always show timestamp
    }

    @MainActor
    public func decorate(_ message: Message) -> AnyView {
        AnyView(
            Text(message.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        )
    }
}
```

---

## Integration

### MessageBubble Change

```swift
// Current (hardcoded timestamp):
VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
    // ... attachments + text ...

    Text(message.date, style: .time)
        .font(.caption2)
        .foregroundStyle(.secondary)
}

// New (decorator-driven):
VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
    // Top decorators
    HStack {
        ForEach(DecoratorRegistry.shared.decorators(for: message, at: .topLeading)) { d in
            d.decorate(message)
        }
        Spacer()
        ForEach(DecoratorRegistry.shared.decorators(for: message, at: .topTrailing)) { d in
            d.decorate(message)
        }
    }

    // Bubble content (attachments + text)
    ZStack {
        VStack(alignment: .leading, spacing: 4) {
            // ... attachments + text ...
        }

        // Overlay decorators
        ForEach(DecoratorRegistry.shared.decorators(for: message, at: .overlay)) { d in
            d.decorate(message)
        }
    }

    // Bottom decorators
    HStack {
        ForEach(DecoratorRegistry.shared.decorators(for: message, at: .bottomLeading)) { d in
            d.decorate(message)
        }
        Spacer()
        ForEach(DecoratorRegistry.shared.decorators(for: message, at: .bottomTrailing)) { d in
            d.decorate(message)
        }
    }

    // Below decorators (timestamp)
    ForEach(DecoratorRegistry.shared.decorators(for: message, at: .below)) { d in
        d.decorate(message)
    }
}
```

Note: For v1 with only TimestampDecorator (.below), most position slots will be empty. The structure is ready for future decorators without modifying MessageBubble.

### App Registration

```swift
func setupDecorators() {
    DecoratorRegistry.shared.register(TimestampDecorator())
}
```

---

## File Structure

**New files:**

```
MessageBridgeClient/Sources/MessageBridgeClientCore/
├── Protocols/
│   └── BubbleDecorator.swift (protocol + DecoratorPosition enum)
├── Registries/
│   └── DecoratorRegistry.swift
└── Decorators/
    └── TimestampDecorator.swift

Tests/MessageBridgeClientCoreTests/
├── Protocols/
│   └── BubbleDecoratorTests.swift
├── Registries/
│   └── DecoratorRegistryTests.swift
├── Decorators/
│   └── TimestampDecoratorTests.swift
└── Mocks/
    └── MockBubbleDecorator.swift
```

**Files to modify:**

| File | Change |
|------|--------|
| `MessageThreadView.swift` | Replace hardcoded timestamp with decorator slots |
| `MessageBridgeApp.swift` | Add setupDecorators() |
| `CLAUDE.md` | Update migration table (Client Decorators → ✅) |

---

## Future Extensions

**TapbackDecorator:**

```swift
struct TapbackDecorator: BubbleDecorator {
    let id = "tapbacks"
    let position = DecoratorPosition.topTrailing

    func shouldDecorate(_ message: Message) -> Bool {
        !(message.tapbacks ?? []).isEmpty
    }

    @MainActor
    func decorate(_ message: Message) -> AnyView {
        AnyView(TapbackPill(tapbacks: message.tapbacks ?? []))
    }
}
```

**ReadReceiptDecorator:**

```swift
struct ReadReceiptDecorator: BubbleDecorator {
    let id = "read-receipt"
    let position = DecoratorPosition.bottomTrailing

    func shouldDecorate(_ message: Message) -> Bool {
        message.isFromMe
    }
}
```

**CodeCopyDecorator:**

```swift
struct CodeCopyDecorator: BubbleDecorator {
    let id = "code-copy"
    let position = DecoratorPosition.overlay

    func shouldDecorate(_ message: Message) -> Bool {
        !(message.detectedCodes ?? []).isEmpty
    }
}
```
