# BubbleDecorator Protocol Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract bubble decorations from MessageBubble into protocol-based decorators with positional slots.

**Architecture:** BubbleDecorator protocol with DecoratorPosition enum, DecoratorRegistry singleton filtering by position, TimestampDecorator as first implementation.

**Tech Stack:** SwiftUI, Swift protocols

---

### Task 1: BubbleDecorator Protocol + DecoratorPosition + Mock

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/BubbleDecorator.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Mocks/MockBubbleDecorator.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Protocols/BubbleDecoratorTests.swift`

**Protocol + enum:**

```swift
// Sources/MessageBridgeClientCore/Protocols/BubbleDecorator.swift
import SwiftUI

/// Position of a decorator relative to the message bubble.
public enum DecoratorPosition: String, Codable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case below
    case overlay
}

/// Protocol for adding decorations around message bubbles.
///
/// Decorators render at specific positions around the bubble content.
/// The DecoratorRegistry filters by position, allowing multiple decorators
/// at different positions to coexist.
public protocol BubbleDecorator: Identifiable, Sendable {
    var id: String { get }
    var position: DecoratorPosition { get }
    func shouldDecorate(_ message: Message) -> Bool
    @MainActor func decorate(_ message: Message) -> AnyView
}
```

**Mock:**

```swift
// Tests/MessageBridgeClientCoreTests/Mocks/MockBubbleDecorator.swift
import SwiftUI
@testable import MessageBridgeClientCore

final class MockBubbleDecorator: BubbleDecorator, @unchecked Sendable {
    let id: String
    let position: DecoratorPosition
    var shouldDecorateResult = true
    var shouldDecorateCallCount = 0

    init(id: String = "mock", position: DecoratorPosition = .below) {
        self.id = id
        self.position = position
    }

    func shouldDecorate(_ message: Message) -> Bool {
        shouldDecorateCallCount += 1
        return shouldDecorateResult
    }

    @MainActor
    func decorate(_ message: Message) -> AnyView {
        AnyView(Text("Mock decoration"))
    }
}
```

**Tests:**

```swift
// Tests/MessageBridgeClientCoreTests/Protocols/BubbleDecoratorTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class BubbleDecoratorTests: XCTestCase {
    func testMock_hasId() {
        XCTAssertEqual(MockBubbleDecorator(id: "test").id, "test")
    }

    func testMock_hasPosition() {
        XCTAssertEqual(MockBubbleDecorator(position: .topTrailing).position, .topTrailing)
    }

    func testMock_shouldDecorate_returnsConfiguredValue() {
        let mock = MockBubbleDecorator()
        let msg = makeMessage()
        mock.shouldDecorateResult = false
        XCTAssertFalse(mock.shouldDecorate(msg))
        mock.shouldDecorateResult = true
        XCTAssertTrue(mock.shouldDecorate(msg))
    }

    func testDecoratorPosition_allCasesExist() {
        _ = DecoratorPosition.topLeading
        _ = DecoratorPosition.topTrailing
        _ = DecoratorPosition.bottomLeading
        _ = DecoratorPosition.bottomTrailing
        _ = DecoratorPosition.below
        _ = DecoratorPosition.overlay
    }

    private func makeMessage() -> Message {
        Message(id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil, conversationId: "c1")
    }
}
```

**Commit:**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/BubbleDecorator.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Mocks/MockBubbleDecorator.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Protocols/BubbleDecoratorTests.swift
git commit -m "feat(client): add BubbleDecorator protocol with DecoratorPosition"
```

---

### Task 2: DecoratorRegistry

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/DecoratorRegistry.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Registries/DecoratorRegistryTests.swift`

**Registry:**

```swift
// Sources/MessageBridgeClientCore/Registries/DecoratorRegistry.swift
import Foundation

/// Singleton registry for bubble decorators.
///
/// Unlike renderer registries which select ONE best match, the decorator
/// registry returns ALL matching decorators for a given position, since
/// multiple decorators can coexist (e.g., tapbacks + timestamp).
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

    /// All decorators that should show for this message at the given position.
    public func decorators(for message: Message, at position: DecoratorPosition) -> [any BubbleDecorator] {
        lock.lock()
        defer { lock.unlock() }
        return decorators.filter { $0.position == position && $0.shouldDecorate(message) }
    }

    public var all: [any BubbleDecorator] {
        lock.lock()
        defer { lock.unlock() }
        return decorators
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        decorators.removeAll()
    }
}
```

**Tests:**

```swift
// Tests/MessageBridgeClientCoreTests/Registries/DecoratorRegistryTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class DecoratorRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DecoratorRegistry.shared.reset()
    }
    override func tearDown() {
        DecoratorRegistry.shared.reset()
        super.tearDown()
    }

    func testShared_isSingleton() {
        XCTAssertTrue(DecoratorRegistry.shared === DecoratorRegistry.shared)
    }

    func testRegister_addsDecorator() {
        DecoratorRegistry.shared.register(MockBubbleDecorator(id: "a"))
        XCTAssertEqual(DecoratorRegistry.shared.all.count, 1)
    }

    func testReset_clears() {
        DecoratorRegistry.shared.register(MockBubbleDecorator(id: "a"))
        DecoratorRegistry.shared.reset()
        XCTAssertTrue(DecoratorRegistry.shared.all.isEmpty)
    }

    func testDecorators_filtersByPosition() {
        let below = MockBubbleDecorator(id: "below", position: .below)
        let top = MockBubbleDecorator(id: "top", position: .topTrailing)
        DecoratorRegistry.shared.register(below)
        DecoratorRegistry.shared.register(top)

        let msg = makeMessage()
        let belowResults = DecoratorRegistry.shared.decorators(for: msg, at: .below)
        XCTAssertEqual(belowResults.count, 1)
        XCTAssertEqual(belowResults[0].id, "below")

        let topResults = DecoratorRegistry.shared.decorators(for: msg, at: .topTrailing)
        XCTAssertEqual(topResults.count, 1)
        XCTAssertEqual(topResults[0].id, "top")
    }

    func testDecorators_filtersByShouldDecorate() {
        let show = MockBubbleDecorator(id: "show", position: .below)
        let hide = MockBubbleDecorator(id: "hide", position: .below)
        hide.shouldDecorateResult = false
        DecoratorRegistry.shared.register(show)
        DecoratorRegistry.shared.register(hide)

        let results = DecoratorRegistry.shared.decorators(for: makeMessage(), at: .below)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "show")
    }

    func testDecorators_returnsMultipleAtSamePosition() {
        let a = MockBubbleDecorator(id: "a", position: .below)
        let b = MockBubbleDecorator(id: "b", position: .below)
        DecoratorRegistry.shared.register(a)
        DecoratorRegistry.shared.register(b)

        let results = DecoratorRegistry.shared.decorators(for: makeMessage(), at: .below)
        XCTAssertEqual(results.count, 2)
    }

    func testDecorators_emptyForUnusedPosition() {
        DecoratorRegistry.shared.register(MockBubbleDecorator(id: "a", position: .below))
        let results = DecoratorRegistry.shared.decorators(for: makeMessage(), at: .overlay)
        XCTAssertTrue(results.isEmpty)
    }

    private func makeMessage() -> Message {
        Message(id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil, conversationId: "c1")
    }
}
```

**Commit:**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/DecoratorRegistry.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Registries/DecoratorRegistryTests.swift
git commit -m "feat(client): add DecoratorRegistry singleton"
```

---

### Task 3: TimestampDecorator

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Decorators/TimestampDecorator.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Decorators/TimestampDecoratorTests.swift`

**Implementation:**

```swift
// Sources/MessageBridgeClientCore/Decorators/TimestampDecorator.swift
import SwiftUI

/// Decorator that shows the message timestamp below the bubble.
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

**Tests:**

```swift
// Tests/MessageBridgeClientCoreTests/Decorators/TimestampDecoratorTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class TimestampDecoratorTests: XCTestCase {
    let decorator = TimestampDecorator()

    func testId() { XCTAssertEqual(decorator.id, "timestamp") }
    func testPosition_isBelow() { XCTAssertEqual(decorator.position, .below) }

    func testShouldDecorate_alwaysTrue() {
        let msg = Message(id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil, conversationId: "c1")
        XCTAssertTrue(decorator.shouldDecorate(msg))
    }

    func testShouldDecorate_nilText_stillTrue() {
        let msg = Message(id: 1, guid: "g1", text: nil, date: Date(), isFromMe: false, handleId: 1, conversationId: "c1")
        XCTAssertTrue(decorator.shouldDecorate(msg))
    }
}
```

**Commit:**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Decorators/TimestampDecorator.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Decorators/TimestampDecoratorTests.swift
git commit -m "feat(client): add TimestampDecorator"
```

---

### Task 4: Integrate into MessageBubble and register

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift`
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/App/MessageBridgeApp.swift`

**MessageBubble change — replace the hardcoded timestamp (line ~141-143) with decorator rendering.**

In the VStack inside MessageBubble, replace:

```swift
Text(message.date, style: .time)
    .font(.caption2)
    .foregroundStyle(.secondary)
```

With decorator slots. The full VStack becomes:

```swift
VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
    // Show sender name in group conversations
    if isGroupConversation && !message.isFromMe && showSenderInfo {
        Text(sender?.displayName ?? "Unknown")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    // Attachments
    if message.hasAttachments {
        AttachmentRendererRegistry.shared.renderer(for: message.attachments)
            .render(message.attachments)
    }

    // Text content
    if message.hasText {
        RendererRegistry.shared.renderer(for: message)
            .render(message)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.isFromMe ? Color.blue : Color(.systemGray).opacity(0.2))
            .foregroundStyle(message.isFromMe ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Below decorators (timestamp, etc.)
    ForEach(DecoratorRegistry.shared.decorators(for: message, at: .below)) { decorator in
        decorator.decorate(message)
    }
}
```

Note: For v1, we only render `.below` decorators since that's where TimestampDecorator lives. Other positions can be added when decorators use them.

**App registration:**

```swift
private func setupDecorators() {
    DecoratorRegistry.shared.register(TimestampDecorator())
}
```

Call `setupDecorators()` in init after the other setup methods.

**Build and test:**

```bash
cd /Users/robertyang/Documents/Repos/Personal/MessageBridge/MessageBridgeClient && swift build && swift test
```

**Commit:**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/
git commit -m "feat(client): integrate DecoratorRegistry into MessageBubble

Replace hardcoded timestamp with decorator-driven positional
rendering. Register TimestampDecorator at app startup."
```

---

### Task 5: Update CLAUDE.md migration table

**Files:**
- Modify: `CLAUDE.md`

Change `Client Decorators` from `🔴 Not migrated` to `✅ Migrated`.

```bash
git add CLAUDE.md
git commit -m "docs: mark Client Decorators as migrated in CLAUDE.md"
```
