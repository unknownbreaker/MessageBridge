# MessageRenderer Protocol Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract text/content rendering from the monolithic MessageBubble into protocol-based renderers with a RendererRegistry.

**Architecture:** MessageRenderer protocol with priority-based selection via RendererRegistry singleton. Four renderers: PlainTextRenderer (fallback), LargeEmojiRenderer, LinkPreviewRenderer, CodeHighlightRenderer. MessageBubble delegates content rendering to the selected renderer while keeping bubble chrome unchanged.

**Tech Stack:** SwiftUI, Swift protocols, NSDataDetector (for URL detection), LinkPresentation (existing)

---

### Task 1: DetectedCode and TextHighlight Models

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/DetectedCode.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/TextHighlight.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Models/DetectedCodeTests.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Models/TextHighlightTests.swift`

**Step 1: Write failing tests for DetectedCode**

```swift
// Tests/MessageBridgeClientCoreTests/Models/DetectedCodeTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class DetectedCodeTests: XCTestCase {
    func testInit_storesValue() {
        let code = DetectedCode(value: "847293")
        XCTAssertEqual(code.value, "847293")
    }

    func testEquatable_sameValues_areEqual() {
        let a = DetectedCode(value: "1234")
        let b = DetectedCode(value: "1234")
        XCTAssertEqual(a, b)
    }

    func testEquatable_differentValues_areNotEqual() {
        let a = DetectedCode(value: "1234")
        let b = DetectedCode(value: "5678")
        XCTAssertNotEqual(a, b)
    }

    func testCodable_roundTrips() throws {
        let code = DetectedCode(value: "G-582941")
        let data = try JSONEncoder().encode(code)
        let decoded = try JSONDecoder().decode(DetectedCode.self, from: data)
        XCTAssertEqual(decoded, code)
    }
}
```

**Step 2: Write failing tests for TextHighlight**

```swift
// Tests/MessageBridgeClientCoreTests/Models/TextHighlightTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class TextHighlightTests: XCTestCase {
    func testInit_storesProperties() {
        let highlight = TextHighlight(text: "847293", type: .code)
        XCTAssertEqual(highlight.text, "847293")
        XCTAssertEqual(highlight.type, .code)
    }

    func testEquatable_sameValues_areEqual() {
        let a = TextHighlight(text: "test", type: .link)
        let b = TextHighlight(text: "test", type: .link)
        XCTAssertEqual(a, b)
    }

    func testAllHighlightTypes_exist() {
        _ = TextHighlight.HighlightType.code
        _ = TextHighlight.HighlightType.link
        _ = TextHighlight.HighlightType.phoneNumber
        _ = TextHighlight.HighlightType.email
    }

    func testCodable_roundTrips() throws {
        let highlight = TextHighlight(text: "https://example.com", type: .link)
        let data = try JSONEncoder().encode(highlight)
        let decoded = try JSONDecoder().decode(TextHighlight.self, from: data)
        XCTAssertEqual(decoded, highlight)
    }
}
```

**Step 3: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: Compilation error — DetectedCode and TextHighlight not found

**Step 4: Implement DetectedCode**

```swift
// Sources/MessageBridgeClientCore/Models/DetectedCode.swift
import Foundation

/// A detected verification/authentication code in a message.
///
/// Populated by the server's CodeDetector processor when it identifies
/// patterns like 2FA codes, OTPs, or verification numbers.
public struct DetectedCode: Codable, Sendable, Equatable {
    /// The code value (e.g., "847293", "G-582941")
    public let value: String

    public init(value: String) {
        self.value = value
    }
}
```

**Step 5: Implement TextHighlight**

```swift
// Sources/MessageBridgeClientCore/Models/TextHighlight.swift
import Foundation

/// A highlight span in message text for rendering emphasis.
///
/// Used by renderers to apply visual styling to detected content
/// such as verification codes, URLs, phone numbers, and emails.
public struct TextHighlight: Codable, Sendable, Equatable {
    /// The text content to highlight
    public let text: String

    /// The type of content detected
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

**Step 6: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 7: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Models/DetectedCode.swift \
       MessageBridgeClient/Sources/MessageBridgeClientCore/Models/TextHighlight.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Models/
git commit -m "feat(client): add DetectedCode and TextHighlight models"
```

---

### Task 2: Add enrichment fields to client Message model

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/Models.swift` (lines 132-165, Message struct)
- Modify: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Models/DetectedCodeTests.swift` (add Message integration tests)

**Step 1: Write failing tests for Message enrichment fields**

Add to a new test file:

```swift
// Tests/MessageBridgeClientCoreTests/Models/MessageEnrichmentTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class MessageEnrichmentTests: XCTestCase {
    func testMessage_defaultEnrichmentFields_areNil() {
        let message = Message(
            id: 1, guid: "g1", text: "Hello", date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        XCTAssertNil(message.detectedCodes)
        XCTAssertNil(message.highlights)
    }

    func testMessage_withDetectedCodes_storesValues() {
        let codes = [DetectedCode(value: "1234")]
        let message = Message(
            id: 1, guid: "g1", text: "Code: 1234", date: Date(),
            isFromMe: false, handleId: 1, conversationId: "c1",
            attachments: [],
            detectedCodes: codes
        )
        XCTAssertEqual(message.detectedCodes?.count, 1)
        XCTAssertEqual(message.detectedCodes?.first?.value, "1234")
    }

    func testMessage_withHighlights_storesValues() {
        let highlights = [TextHighlight(text: "https://example.com", type: .link)]
        let message = Message(
            id: 1, guid: "g1", text: "Visit https://example.com", date: Date(),
            isFromMe: false, handleId: 1, conversationId: "c1",
            attachments: [],
            detectedCodes: nil,
            highlights: highlights
        )
        XCTAssertEqual(message.highlights?.count, 1)
    }

    func testMessage_codable_roundTripsWithEnrichments() throws {
        let codes = [DetectedCode(value: "5678")]
        let highlights = [TextHighlight(text: "5678", type: .code)]
        let message = Message(
            id: 1, guid: "g1", text: "Code is 5678", date: Date(),
            isFromMe: false, handleId: 1, conversationId: "c1",
            attachments: [],
            detectedCodes: codes,
            highlights: highlights
        )
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.detectedCodes, codes)
        XCTAssertEqual(decoded.highlights, highlights)
    }

    func testMessage_codable_decodesWithoutEnrichmentFields() throws {
        // Server may not send these fields — they should default to nil
        let json = """
        {
            "id": 1,
            "guid": "g1",
            "text": "Hello",
            "date": 0,
            "isFromMe": true,
            "conversationId": "c1",
            "attachments": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(Message.self, from: json)
        XCTAssertNil(message.detectedCodes)
        XCTAssertNil(message.highlights)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: Compilation error — Message has no detectedCodes/highlights properties

**Step 3: Add enrichment fields to Message**

In `Models.swift`, add to the Message struct after `attachments`:

```swift
public let detectedCodes: [DetectedCode]?
public let highlights: [TextHighlight]?
```

Update the `init` to include these with default nil values:

```swift
public init(
    id: Int64, guid: String, text: String?, date: Date, isFromMe: Bool, handleId: Int64?,
    conversationId: String, attachments: [Attachment] = [],
    detectedCodes: [DetectedCode]? = nil,
    highlights: [TextHighlight]? = nil
) {
    self.id = id
    self.guid = guid
    self.text = text
    self.date = date
    self.isFromMe = isFromMe
    self.handleId = handleId
    self.conversationId = conversationId
    self.attachments = attachments
    self.detectedCodes = detectedCodes
    self.highlights = highlights
}
```

Add `CodingKeys` enum to handle optional decoding gracefully (server may not send these):

```swift
enum CodingKeys: String, CodingKey {
    case id, guid, text, date, isFromMe, handleId, conversationId, attachments
    case detectedCodes, highlights
}

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int64.self, forKey: .id)
    guid = try container.decode(String.self, forKey: .guid)
    text = try container.decodeIfPresent(String.self, forKey: .text)
    date = try container.decode(Date.self, forKey: .date)
    isFromMe = try container.decode(Bool.self, forKey: .isFromMe)
    handleId = try container.decodeIfPresent(Int64.self, forKey: .handleId)
    conversationId = try container.decode(String.self, forKey: .conversationId)
    attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    detectedCodes = try container.decodeIfPresent([DetectedCode].self, forKey: .detectedCodes)
    highlights = try container.decodeIfPresent([TextHighlight].self, forKey: .highlights)
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Models/Models.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Models/MessageEnrichmentTests.swift
git commit -m "feat(client): add enrichment fields to Message model

Add detectedCodes and highlights optional fields for server-side
message processing enrichments. Gracefully handles missing fields
in JSON from servers that don't yet send them."
```

---

### Task 3: MessageRenderer Protocol

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/MessageRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Protocols/MessageRendererTests.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Mocks/MockMessageRenderer.swift`

**Step 1: Write failing tests**

```swift
// Tests/MessageBridgeClientCoreTests/Mocks/MockMessageRenderer.swift
import SwiftUI
@testable import MessageBridgeClientCore

final class MockMessageRenderer: MessageRenderer, @unchecked Sendable {
    let id: String
    let priority: Int
    var canRenderResult = true
    var canRenderCallCount = 0
    var renderCallCount = 0

    init(id: String = "mock", priority: Int = 0) {
        self.id = id
        self.priority = priority
    }

    func canRender(_ message: Message) -> Bool {
        canRenderCallCount += 1
        return canRenderResult
    }

    @MainActor
    func render(_ message: Message) -> AnyView {
        renderCallCount += 1
        return AnyView(Text("Mock: \(message.text ?? "")"))
    }
}
```

```swift
// Tests/MessageBridgeClientCoreTests/Protocols/MessageRendererTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class MessageRendererTests: XCTestCase {
    func testMockRenderer_hasId() {
        let renderer = MockMessageRenderer(id: "test-renderer")
        XCTAssertEqual(renderer.id, "test-renderer")
    }

    func testMockRenderer_hasPriority() {
        let renderer = MockMessageRenderer(priority: 50)
        XCTAssertEqual(renderer.priority, 50)
    }

    func testMockRenderer_canRender_returnsConfiguredValue() {
        let message = Message(
            id: 1, guid: "g1", text: "Hello", date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        let renderer = MockMessageRenderer()
        renderer.canRenderResult = false
        XCTAssertFalse(renderer.canRender(message))
        renderer.canRenderResult = true
        XCTAssertTrue(renderer.canRender(message))
    }

    func testMockRenderer_canRender_incrementsCallCount() {
        let message = Message(
            id: 1, guid: "g1", text: "Hello", date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        let renderer = MockMessageRenderer()
        _ = renderer.canRender(message)
        _ = renderer.canRender(message)
        XCTAssertEqual(renderer.canRenderCallCount, 2)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: Compilation error — MessageRenderer protocol not found

**Step 3: Implement the protocol**

```swift
// Sources/MessageBridgeClientCore/Protocols/MessageRenderer.swift
import SwiftUI

/// Protocol for rendering message text content.
///
/// Implementations handle different content types (plain text, link previews,
/// large emoji, code highlights). The RendererRegistry selects the highest-priority
/// renderer whose `canRender` returns true for a given message.
///
/// Renderers only handle the text/content area of a message bubble.
/// Bubble chrome (avatar, timestamp, background) is managed by MessageBubble.
public protocol MessageRenderer: Identifiable, Sendable {
    /// Unique identifier for this renderer
    var id: String { get }

    /// Priority for renderer selection. Higher priority renderers are checked first.
    var priority: Int { get }

    /// Whether this renderer can handle the given message.
    func canRender(_ message: Message) -> Bool

    /// Render the message content.
    @MainActor func render(_ message: Message) -> AnyView
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/ \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Protocols/ \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Mocks/
git commit -m "feat(client): add MessageRenderer protocol and mock"
```

---

### Task 4: RendererRegistry

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/RendererRegistry.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Registries/RendererRegistryTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/MessageBridgeClientCoreTests/Registries/RendererRegistryTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class RendererRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RendererRegistry.shared.reset()
    }

    override func tearDown() {
        RendererRegistry.shared.reset()
        super.tearDown()
    }

    func testShared_isSingleton() {
        let a = RendererRegistry.shared
        let b = RendererRegistry.shared
        XCTAssertTrue(a === b)
    }

    func testRegister_addsRenderer() {
        let renderer = MockMessageRenderer(id: "test")
        RendererRegistry.shared.register(renderer)
        XCTAssertEqual(RendererRegistry.shared.all.count, 1)
    }

    func testAll_returnsRegisteredRenderers() {
        RendererRegistry.shared.register(MockMessageRenderer(id: "a"))
        RendererRegistry.shared.register(MockMessageRenderer(id: "b"))
        let ids = RendererRegistry.shared.all.map { $0.id }
        XCTAssertTrue(ids.contains("a"))
        XCTAssertTrue(ids.contains("b"))
    }

    func testReset_clearsAllRenderers() {
        RendererRegistry.shared.register(MockMessageRenderer(id: "test"))
        RendererRegistry.shared.reset()
        XCTAssertTrue(RendererRegistry.shared.all.isEmpty)
    }

    func testRenderer_selectsHighestPriorityMatch() {
        let low = MockMessageRenderer(id: "low", priority: 0)
        let high = MockMessageRenderer(id: "high", priority: 100)
        RendererRegistry.shared.register(low)
        RendererRegistry.shared.register(high)

        let message = Message(
            id: 1, guid: "g1", text: "Hello", date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        let selected = RendererRegistry.shared.renderer(for: message)
        XCTAssertEqual(selected.id, "high")
    }

    func testRenderer_skipsNonMatching() {
        let noMatch = MockMessageRenderer(id: "no-match", priority: 100)
        noMatch.canRenderResult = false
        let fallback = MockMessageRenderer(id: "fallback", priority: 0)
        RendererRegistry.shared.register(noMatch)
        RendererRegistry.shared.register(fallback)

        let message = Message(
            id: 1, guid: "g1", text: "Hello", date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        let selected = RendererRegistry.shared.renderer(for: message)
        XCTAssertEqual(selected.id, "fallback")
    }

    func testRenderer_emptyRegistry_returnsPlainTextRenderer() {
        let message = Message(
            id: 1, guid: "g1", text: "Hello", date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        let selected = RendererRegistry.shared.renderer(for: message)
        XCTAssertEqual(selected.id, "plain-text")
    }
}
```

Note: The last test depends on PlainTextRenderer existing (Task 5). When implementing, initially it can return a basic fallback. Once Task 5 is done, this test will work properly.

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: Compilation error — RendererRegistry not found

**Step 3: Implement RendererRegistry**

```swift
// Sources/MessageBridgeClientCore/Registries/RendererRegistry.swift
import Foundation

/// Singleton registry for message content renderers.
///
/// Renderers are selected by priority — highest priority renderer whose
/// `canRender` returns true is used. Falls back to PlainTextRenderer
/// when no registered renderer matches.
public final class RendererRegistry: @unchecked Sendable {
    public static let shared = RendererRegistry()

    private var renderers: [any MessageRenderer] = []
    private let lock = NSLock()

    private init() {}

    /// Register a renderer.
    public func register(_ renderer: any MessageRenderer) {
        lock.lock()
        defer { lock.unlock() }
        renderers.append(renderer)
    }

    /// Find the best renderer for a message.
    ///
    /// Returns the highest-priority renderer whose `canRender` returns true.
    /// Falls back to `PlainTextRenderer` if no registered renderer matches.
    public func renderer(for message: Message) -> any MessageRenderer {
        lock.lock()
        defer { lock.unlock() }
        return renderers
            .sorted { $0.priority > $1.priority }
            .first { $0.canRender(message) }
            ?? PlainTextRenderer()
    }

    /// All registered renderers.
    public var all: [any MessageRenderer] {
        lock.lock()
        defer { lock.unlock() }
        return renderers
    }

    /// Reset for testing.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        renderers.removeAll()
    }
}
```

Note: This depends on PlainTextRenderer (Task 5) for the fallback. Implement Task 5 immediately after to make tests pass.

**Step 4: Run tests — some may fail until PlainTextRenderer exists (Task 5)**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: Most pass, `testRenderer_emptyRegistry_returnsPlainTextRenderer` may need Task 5

**Step 5: Commit (after Task 5 if needed for compilation)**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/ \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Registries/
git commit -m "feat(client): add RendererRegistry singleton"
```

---

### Task 5: PlainTextRenderer (fallback)

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/PlainTextRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/PlainTextRendererTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/MessageBridgeClientCoreTests/Renderers/PlainTextRendererTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class PlainTextRendererTests: XCTestCase {
    let renderer = PlainTextRenderer()

    func testId_isPlainText() {
        XCTAssertEqual(renderer.id, "plain-text")
    }

    func testPriority_isZero() {
        XCTAssertEqual(renderer.priority, 0)
    }

    func testCanRender_alwaysReturnsTrue() {
        let withText = Message(
            id: 1, guid: "g1", text: "Hello", date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        let withNilText = Message(
            id: 2, guid: "g2", text: nil, date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        let emptyText = Message(
            id: 3, guid: "g3", text: "", date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
        XCTAssertTrue(renderer.canRender(withText))
        XCTAssertTrue(renderer.canRender(withNilText))
        XCTAssertTrue(renderer.canRender(emptyText))
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: Compilation error — PlainTextRenderer not found

**Step 3: Implement PlainTextRenderer**

```swift
// Sources/MessageBridgeClientCore/Renderers/Messages/PlainTextRenderer.swift
import SwiftUI

/// Default fallback renderer for plain text messages.
///
/// Always returns `true` from `canRender` — this is the last-resort renderer
/// used when no higher-priority renderer matches the message.
public struct PlainTextRenderer: MessageRenderer {
    public let id = "plain-text"
    public let priority = 0

    public init() {}

    public func canRender(_ message: Message) -> Bool {
        true
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

**Step 4: Run tests to verify they pass (including RendererRegistry fallback test)**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 5: Commit (together with Task 4 if they were co-dependent)**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/ \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/
git commit -m "feat(client): add PlainTextRenderer (fallback renderer)"
```

---

### Task 6: LargeEmojiRenderer

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/LargeEmojiRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/LargeEmojiRendererTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/MessageBridgeClientCoreTests/Renderers/LargeEmojiRendererTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class LargeEmojiRendererTests: XCTestCase {
    let renderer = LargeEmojiRenderer()

    func testId_isLargeEmoji() {
        XCTAssertEqual(renderer.id, "large-emoji")
    }

    func testPriority_is50() {
        XCTAssertEqual(renderer.priority, 50)
    }

    func testCanRender_singleEmoji_returnsTrue() {
        let message = makeMessage("😀")
        XCTAssertTrue(renderer.canRender(message))
    }

    func testCanRender_twoEmojis_returnsTrue() {
        let message = makeMessage("😀🎉")
        XCTAssertTrue(renderer.canRender(message))
    }

    func testCanRender_threeEmojis_returnsTrue() {
        let message = makeMessage("😀🎉🔥")
        XCTAssertTrue(renderer.canRender(message))
    }

    func testCanRender_fourEmojis_returnsFalse() {
        let message = makeMessage("😀🎉🔥❤️")
        XCTAssertFalse(renderer.canRender(message))
    }

    func testCanRender_textWithEmoji_returnsFalse() {
        let message = makeMessage("Hello 😀")
        XCTAssertFalse(renderer.canRender(message))
    }

    func testCanRender_plainText_returnsFalse() {
        let message = makeMessage("Hello world")
        XCTAssertFalse(renderer.canRender(message))
    }

    func testCanRender_nilText_returnsFalse() {
        let message = makeMessage(nil)
        XCTAssertFalse(renderer.canRender(message))
    }

    func testCanRender_emptyText_returnsFalse() {
        let message = makeMessage("")
        XCTAssertFalse(renderer.canRender(message))
    }

    func testCanRender_numbersOnly_returnsFalse() {
        let message = makeMessage("123")
        XCTAssertFalse(renderer.canRender(message))
    }

    private func makeMessage(_ text: String?) -> Message {
        Message(
            id: 1, guid: "g1", text: text, date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test --filter LargeEmoji 2>&1 | tail -20`
Expected: Compilation error — LargeEmojiRenderer not found

**Step 3: Implement LargeEmojiRenderer**

```swift
// Sources/MessageBridgeClientCore/Renderers/Messages/LargeEmojiRenderer.swift
import SwiftUI

/// Renderer for messages containing only 1-3 emoji characters.
///
/// Displays emoji at a larger font size without a bubble background,
/// matching the Apple Messages behavior for emoji-only messages.
public struct LargeEmojiRenderer: MessageRenderer {
    public let id = "large-emoji"
    public let priority = 50

    public init() {}

    public func canRender(_ message: Message) -> Bool {
        guard let text = message.text, !text.isEmpty else { return false }
        let emojiCount = text.unicodeScalars.filter { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && !$0.isASCII) }.count
        let isAllEmoji = text.allSatisfy { $0.isEmoji }
        return isAllEmoji && emojiCount >= 1 && emojiCount <= 3
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

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation ||
               (scalar.properties.isEmoji && !scalar.isASCII)
    }
}

extension Unicode.Scalar {
    var isASCII: Bool {
        value <= 0x7F
    }
}
```

Note: Emoji detection is tricky. The `Character.isEmoji` extension checks `isEmojiPresentation` (guaranteed emoji like 😀) or `isEmoji && !isASCII` (avoids treating # or digits as emoji). You may need to adjust the `canRender` logic to correctly count grapheme clusters vs scalars — test with compound emoji like 👨‍👩‍👧.

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter LargeEmoji 2>&1 | tail -20`
Expected: All tests pass. If emoji detection is off, adjust the implementation.

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/LargeEmojiRenderer.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/LargeEmojiRendererTests.swift
git commit -m "feat(client): add LargeEmojiRenderer for emoji-only messages"
```

---

### Task 7: LinkPreviewRenderer

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/LinkPreviewRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/LinkPreviewRendererTests.swift`

**Context:** The existing `LinkPreviewView` (in `MessageBridgeClient/Sources/MessageBridgeClient/Views/LinkPreviewView.swift`) uses `LPMetadataProvider` for client-side fetching. The existing `URLDetector` (in `MessageBridgeClientCore/Services/URLDetector.swift`) provides `firstURL(in:)` and `containsURL(in:)`. The renderer wraps these existing components.

**Important:** Since `LinkPreviewView` is in the `MessageBridgeClient` target (not `MessageBridgeClientCore`), the renderer in `MessageBridgeClientCore` cannot directly reference it. The renderer should detect URLs and expose the first URL, but the actual `LinkPreviewView` rendering must happen at the view layer. Two options:
- Option A: Move `LinkPreviewView` to `MessageBridgeClientCore`
- Option B: Have the renderer render text + a URL indicator, and let the view layer add `LinkPreviewView`

**Chosen approach: Option A** — Move `LinkPreviewView` and its dependencies to `MessageBridgeClientCore` so the renderer can use it directly. However, `LinkPreviewView` uses `LinkPresentation` framework which requires AppKit. Since `MessageBridgeClientCore` currently has no UI dependencies, the cleaner approach is to keep the renderer logic (canRender + URL detection) in Core, and compose with `LinkPreviewView` at the view layer.

**Revised approach:** The `LinkPreviewRenderer` lives in the `MessageBridgeClient` target (not Core) since it needs `LinkPreviewView`. The protocol and registry live in Core. Renderers that need UI from the app target register themselves from the app target.

**Step 1: Write failing tests (canRender logic only, tested without rendering)**

```swift
// Tests/MessageBridgeClientCoreTests/Renderers/LinkPreviewRendererTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class LinkPreviewRendererTests: XCTestCase {
    func testCanRender_withURL_returnsTrue() {
        let message = makeMessage("Check https://apple.com")
        XCTAssertTrue(LinkPreviewRenderer.canRenderMessage(message))
    }

    func testCanRender_withoutURL_returnsFalse() {
        let message = makeMessage("No links here")
        XCTAssertFalse(LinkPreviewRenderer.canRenderMessage(message))
    }

    func testCanRender_nilText_returnsFalse() {
        let message = makeMessage(nil)
        XCTAssertFalse(LinkPreviewRenderer.canRenderMessage(message))
    }

    func testCanRender_emptyText_returnsFalse() {
        let message = makeMessage("")
        XCTAssertFalse(LinkPreviewRenderer.canRenderMessage(message))
    }

    func testId_isLinkPreview() {
        let renderer = LinkPreviewRenderer()
        XCTAssertEqual(renderer.id, "link-preview")
    }

    func testPriority_is100() {
        let renderer = LinkPreviewRenderer()
        XCTAssertEqual(renderer.priority, 100)
    }

    private func makeMessage(_ text: String?) -> Message {
        Message(
            id: 1, guid: "g1", text: text, date: Date(),
            isFromMe: true, handleId: nil, conversationId: "c1"
        )
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test --filter LinkPreviewRenderer 2>&1 | tail -20`
Expected: Compilation error — LinkPreviewRenderer not found

**Step 3: Implement LinkPreviewRenderer in MessageBridgeClientCore**

Since `LinkPreviewView` is in the app target, the renderer will render text + call `URLDetector` to find the URL, then render using a generic view that can be composed. For simplicity in v1, the renderer renders text and a simple link card using `Link` view (no LPMetadataProvider). The existing `LinkPreviewView` integration happens in MessageBubble.

Actually, the simplest approach: put the renderer in Core with a basic link rendering. The existing `LinkPreviewView` in MessageBubble can be removed once the renderer handles it.

```swift
// Sources/MessageBridgeClientCore/Renderers/Messages/LinkPreviewRenderer.swift
import SwiftUI

/// Renderer for messages containing URLs.
///
/// Displays the message text followed by a link preview card.
/// Uses URLDetector (in Core) for URL detection.
public struct LinkPreviewRenderer: MessageRenderer {
    public let id = "link-preview"
    public let priority = 100

    public init() {}

    public func canRender(_ message: Message) -> Bool {
        Self.canRenderMessage(message)
    }

    /// Static method for testability without needing to instantiate.
    public static func canRenderMessage(_ message: Message) -> Bool {
        guard let text = message.text, !text.isEmpty else { return false }
        return URLDetector.containsURL(in: text)
    }

    @MainActor
    public func render(_ message: Message) -> AnyView {
        let text = message.text ?? ""
        let url = URLDetector.firstURL(in: text)

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .textSelection(.enabled)

                if let url = url {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.host ?? url.absoluteString)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(url.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: 280)
                }
            }
        )
    }
}
```

Note: This replaces the existing `LinkPreviewView` integration in MessageBubble. The `LPMetadataProvider`-based rich previews can be added back later as an enhancement to this renderer.

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter LinkPreviewRenderer 2>&1 | tail -20`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/LinkPreviewRenderer.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/LinkPreviewRendererTests.swift
git commit -m "feat(client): add LinkPreviewRenderer for URL-containing messages"
```

---

### Task 8: CodeHighlightRenderer

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/CodeHighlightRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/CodeHighlightRendererTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/MessageBridgeClientCoreTests/Renderers/CodeHighlightRendererTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class CodeHighlightRendererTests: XCTestCase {
    let renderer = CodeHighlightRenderer()

    func testId_isCodeHighlight() {
        XCTAssertEqual(renderer.id, "code-highlight")
    }

    func testPriority_is100() {
        XCTAssertEqual(renderer.priority, 100)
    }

    func testCanRender_withDetectedCodes_returnsTrue() {
        let message = Message(
            id: 1, guid: "g1", text: "Your code is 847293", date: Date(),
            isFromMe: false, handleId: 1, conversationId: "c1",
            attachments: [],
            detectedCodes: [DetectedCode(value: "847293")]
        )
        XCTAssertTrue(renderer.canRender(message))
    }

    func testCanRender_withEmptyCodes_returnsFalse() {
        let message = Message(
            id: 1, guid: "g1", text: "No codes", date: Date(),
            isFromMe: false, handleId: 1, conversationId: "c1",
            attachments: [],
            detectedCodes: []
        )
        XCTAssertFalse(renderer.canRender(message))
    }

    func testCanRender_withNilCodes_returnsFalse() {
        let message = Message(
            id: 1, guid: "g1", text: "No codes", date: Date(),
            isFromMe: false, handleId: 1, conversationId: "c1"
        )
        XCTAssertFalse(renderer.canRender(message))
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test --filter CodeHighlight 2>&1 | tail -20`
Expected: Compilation error — CodeHighlightRenderer not found

**Step 3: Implement CodeHighlightRenderer**

```swift
// Sources/MessageBridgeClientCore/Renderers/Messages/CodeHighlightRenderer.swift
import SwiftUI

/// Renderer for messages with detected verification/authentication codes.
///
/// Highlights detected codes in the message text and shows a "Copy Code"
/// button for quick clipboard access. Only activates when the server's
/// CodeDetector processor has identified codes in the message.
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
            CodeHighlightView(
                text: message.text ?? "",
                codes: message.detectedCodes ?? []
            )
        )
    }
}

struct CodeHighlightView: View {
    let text: String
    let codes: [DetectedCode]
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(highlightedText)
                .textSelection(.enabled)

            if let code = codes.first {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.value, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy \(code.value)")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(.separator))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var highlightedText: AttributedString {
        var result = AttributedString(text)
        for code in codes {
            if let range = result.range(of: code.value) {
                result[range].backgroundColor = .yellow.opacity(0.3)
                result[range].font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            }
        }
        return result
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter CodeHighlight 2>&1 | tail -20`
Expected: All tests pass

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/CodeHighlightRenderer.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/CodeHighlightRendererTests.swift
git commit -m "feat(client): add CodeHighlightRenderer for verification codes"
```

---

### Task 9: Integrate into MessageBubble and register renderers

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift` (lines 124-144 in MessageBubble)
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/App/ClientApp.swift` (or equivalent app entry point)

**Context:**
- Current MessageBubble text rendering (lines 132-144):
  ```swift
  if let text = message.text, !text.isEmpty {
      Text(text)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(message.isFromMe ? Color.blue : Color(.systemGray).opacity(0.2))
          .foregroundStyle(message.isFromMe ? .white : .primary)
          .clipShape(RoundedRectangle(cornerRadius: 16))
      if let firstURL = URLDetector.firstURL(in: text) {
          LinkPreviewView(url: firstURL)
      }
  }
  ```
- Replace with renderer delegation

**Step 1: Add renderer registration to app startup**

Find the app entry point. Look for `@main` or `App` struct:

```swift
// In the app entry or initialization, add:
func setupRenderers() {
    RendererRegistry.shared.register(PlainTextRenderer())
    RendererRegistry.shared.register(LargeEmojiRenderer())
    RendererRegistry.shared.register(LinkPreviewRenderer())
    RendererRegistry.shared.register(CodeHighlightRenderer())
}
```

Call `setupRenderers()` at app launch.

**Step 2: Replace MessageBubble text rendering with renderer**

Replace lines 132-144 in MessageBubble:

```swift
// OLD:
if let text = message.text, !text.isEmpty {
    Text(text)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(message.isFromMe ? Color.blue : Color(.systemGray).opacity(0.2))
        .foregroundStyle(message.isFromMe ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    if let firstURL = URLDetector.firstURL(in: text) {
        LinkPreviewView(url: firstURL)
    }
}

// NEW:
if message.hasText {
    RendererRegistry.shared.renderer(for: message)
        .render(message)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(message.isFromMe ? Color.blue : Color(.systemGray).opacity(0.2))
        .foregroundStyle(message.isFromMe ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
}
```

Note: The bubble chrome (padding, background, foreground, clip shape) stays on the outside. The renderer only provides the inner content.

**Step 3: Build and verify**

Run: `cd MessageBridgeClient && swift build 2>&1 | tail -20`
Expected: Clean build

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 4: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift \
       MessageBridgeClient/Sources/MessageBridgeClient/App/
git commit -m "feat(client): integrate RendererRegistry into MessageBubble

Replace hardcoded text rendering with protocol-based renderer
selection. Register PlainText, LargeEmoji, LinkPreview, and
CodeHighlight renderers at app startup."
```

---

### Task 10: Update CLAUDE.md migration table

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the migration table**

Change `Client Renderers` row from `🔴 Not migrated` to `✅ Migrated`.

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: mark Client Renderers as migrated in CLAUDE.md"
```
