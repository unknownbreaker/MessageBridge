# ComposerPlugin Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate the composer from a hardcoded `ComposeView` to a protocol-driven `ComposerPlugin` architecture with expanding text editor and toolbar infrastructure.

**Architecture:** Define `ComposerPlugin` protocol + `ComposerRegistry` singleton (same pattern as `MessageAction`/`ActionRegistry`). Replace the inline `ComposeView` in `MessageThreadView` with a new `ComposerView` that uses `ExpandingTextEditor` (single-line → 6 lines → scroll) and `ComposerToolbar` (renders buttons from registry). Enter sends, Shift+Enter for newline.

**Tech Stack:** Swift, SwiftUI, macOS 14+, XCTest

---

### Task 1: DraftAttachment Model

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/DraftAttachment.swift`

**Step 1: Create the model**

```swift
import Foundation

/// A draft attachment queued for sending, not yet uploaded.
public struct DraftAttachment: Identifiable, Sendable, Equatable {
  public let id: String
  public let url: URL
  public let type: AttachmentType
  public let fileName: String

  public init(id: String = UUID().uuidString, url: URL, type: AttachmentType, fileName: String) {
    self.id = id
    self.url = url
    self.type = type
    self.fileName = fileName
  }
}
```

**Step 2: Build to verify it compiles**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Models/DraftAttachment.swift
git commit -m "feat(client): add DraftAttachment model"
```

---

### Task 2: ComposerPlugin Protocol & ComposerContext

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/ComposerPlugin.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Composer/ComposerPluginTests.swift`

**Step 1: Write the failing test**

```swift
import SwiftUI
import XCTest

@testable import MessageBridgeClientCore

// MARK: - Mock Plugin

struct MockComposerPlugin: ComposerPlugin {
  let id: String
  let icon: String
  let keyboardShortcut: KeyEquivalent? = nil
  let modifiers: EventModifiers = []

  var shouldShowToolbar: Bool = true
  var activateHandler: (@MainActor () async -> Void)?

  func showsToolbarButton(context: any ComposerContext) -> Bool {
    shouldShowToolbar
  }

  @MainActor
  func activate(context: any ComposerContext) async {
    await activateHandler?()
  }
}

// MARK: - Mock Context

@MainActor
final class MockComposerContext: ComposerContext {
  var text: String = ""
  var attachments: [DraftAttachment] = []
  var insertedTexts: [String] = []
  var addedAttachments: [DraftAttachment] = []
  var removedAttachmentIds: [String] = []
  var presentedSheet = false
  var dismissedSheet = false
  var sendCalled = false

  func insertText(_ text: String) {
    insertedTexts.append(text)
    self.text += text
  }

  func addAttachment(_ attachment: DraftAttachment) {
    addedAttachments.append(attachment)
    attachments.append(attachment)
  }

  func removeAttachment(_ id: String) {
    removedAttachmentIds.append(id)
    attachments.removeAll { $0.id == id }
  }

  func presentSheet(_ view: AnyView) {
    presentedSheet = true
  }

  func dismissSheet() {
    dismissedSheet = true
  }

  func send() async {
    sendCalled = true
  }
}

// MARK: - Tests

final class ComposerPluginTests: XCTestCase {
  func testPluginConformsToIdentifiable() {
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip")
    XCTAssertEqual(plugin.id, "test")
  }

  func testPluginIcon() {
    let plugin = MockComposerPlugin(id: "test", icon: "mic")
    XCTAssertEqual(plugin.icon, "mic")
  }

  func testPluginShowsToolbarButton() {
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip", shouldShowToolbar: true)
    let context = MockComposerContext()
    XCTAssertTrue(plugin.showsToolbarButton(context: context))
  }

  func testPluginHidesToolbarButton() {
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip", shouldShowToolbar: false)
    let context = MockComposerContext()
    XCTAssertFalse(plugin.showsToolbarButton(context: context))
  }

  @MainActor
  func testPluginActivate() async {
    var activated = false
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip") {
      activated = true
    }
    let context = MockComposerContext()
    await plugin.activate(context: context)
    XCTAssertTrue(activated)
  }
}

final class ComposerContextTests: XCTestCase {
  @MainActor
  func testInsertText() {
    let context = MockComposerContext()
    context.insertText("Hello")
    XCTAssertEqual(context.text, "Hello")
    XCTAssertEqual(context.insertedTexts, ["Hello"])
  }

  @MainActor
  func testInsertTextAppends() {
    let context = MockComposerContext()
    context.text = "Hi "
    context.insertText("there")
    XCTAssertEqual(context.text, "Hi there")
  }

  @MainActor
  func testAddAttachment() {
    let context = MockComposerContext()
    let attachment = DraftAttachment(
      url: URL(fileURLWithPath: "/tmp/test.png"),
      type: .image,
      fileName: "test.png"
    )
    context.addAttachment(attachment)
    XCTAssertEqual(context.attachments.count, 1)
    XCTAssertEqual(context.addedAttachments.count, 1)
  }

  @MainActor
  func testRemoveAttachment() {
    let context = MockComposerContext()
    let attachment = DraftAttachment(
      id: "att-1",
      url: URL(fileURLWithPath: "/tmp/test.png"),
      type: .image,
      fileName: "test.png"
    )
    context.attachments = [attachment]
    context.removeAttachment("att-1")
    XCTAssertTrue(context.attachments.isEmpty)
    XCTAssertEqual(context.removedAttachmentIds, ["att-1"])
  }

  @MainActor
  func testSend() async {
    let context = MockComposerContext()
    await context.send()
    XCTAssertTrue(context.sendCalled)
  }

  @MainActor
  func testPresentAndDismissSheet() {
    let context = MockComposerContext()
    context.presentSheet(AnyView(EmptyView()))
    XCTAssertTrue(context.presentedSheet)
    context.dismissSheet()
    XCTAssertTrue(context.dismissedSheet)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeClient && swift test --filter ComposerPluginTests 2>&1 | head -20`
Expected: FAIL — `ComposerPlugin`, `ComposerContext` not defined

**Step 3: Write the protocol**

Create `MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/ComposerPlugin.swift`:

```swift
import SwiftUI

/// Protocol for plugins that add features to the message compose area.
///
/// Plugins can provide toolbar buttons and respond to activation
/// (toolbar tap or keyboard shortcut). Register plugins in
/// `ComposerRegistry` at app launch.
public protocol ComposerPlugin: Identifiable, Sendable {
  var id: String { get }
  var icon: String { get }
  var keyboardShortcut: KeyEquivalent? { get }
  var modifiers: EventModifiers { get }

  /// Whether this plugin should show a toolbar button.
  func showsToolbarButton(context: any ComposerContext) -> Bool

  /// Handle activation (toolbar tap or keyboard shortcut).
  @MainActor func activate(context: any ComposerContext) async
}

/// The interface plugins use to interact with the composer.
@MainActor
public protocol ComposerContext: AnyObject {
  var text: String { get set }
  var attachments: [DraftAttachment] { get set }

  func insertText(_ text: String)
  func addAttachment(_ attachment: DraftAttachment)
  func removeAttachment(_ id: String)
  func presentSheet(_ view: AnyView)
  func dismissSheet()
  func send() async
}

/// Events from the text editor that determine send vs newline behavior.
public enum SubmitEvent {
  case enter
  case shiftEnter
  case optionEnter
  case commandEnter
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter "ComposerPluginTests|ComposerContextTests" 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/ComposerPlugin.swift \
  MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Composer/ComposerPluginTests.swift
git commit -m "feat(client): add ComposerPlugin protocol and ComposerContext"
```

---

### Task 3: ComposerRegistry

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/ComposerRegistry.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Composer/ComposerRegistryTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest

@testable import MessageBridgeClientCore

final class ComposerRegistryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    ComposerRegistry.shared.reset()
  }

  func testStartsEmpty() {
    XCTAssertTrue(ComposerRegistry.shared.all.isEmpty)
  }

  func testRegister() {
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip")
    ComposerRegistry.shared.register(plugin)
    XCTAssertEqual(ComposerRegistry.shared.all.count, 1)
    XCTAssertEqual(ComposerRegistry.shared.all.first?.id, "test")
  }

  func testRegisterMultiple_preservesOrder() {
    ComposerRegistry.shared.register(MockComposerPlugin(id: "a", icon: "a"))
    ComposerRegistry.shared.register(MockComposerPlugin(id: "b", icon: "b"))
    ComposerRegistry.shared.register(MockComposerPlugin(id: "c", icon: "c"))
    let ids = ComposerRegistry.shared.all.map(\.id)
    XCTAssertEqual(ids, ["a", "b", "c"])
  }

  func testUnregister() {
    ComposerRegistry.shared.register(MockComposerPlugin(id: "a", icon: "a"))
    ComposerRegistry.shared.register(MockComposerPlugin(id: "b", icon: "b"))
    ComposerRegistry.shared.unregister("a")
    XCTAssertEqual(ComposerRegistry.shared.all.count, 1)
    XCTAssertEqual(ComposerRegistry.shared.all.first?.id, "b")
  }

  func testUnregister_nonexistent_noOp() {
    ComposerRegistry.shared.register(MockComposerPlugin(id: "a", icon: "a"))
    ComposerRegistry.shared.unregister("zzz")
    XCTAssertEqual(ComposerRegistry.shared.all.count, 1)
  }

  func testReset() {
    ComposerRegistry.shared.register(MockComposerPlugin(id: "a", icon: "a"))
    ComposerRegistry.shared.reset()
    XCTAssertTrue(ComposerRegistry.shared.all.isEmpty)
  }

  func testThreadSafety() {
    let expectation = expectation(description: "concurrent access")
    expectation.expectedFulfillmentCount = 100

    for i in 0..<100 {
      DispatchQueue.global().async {
        ComposerRegistry.shared.register(MockComposerPlugin(id: "p\(i)", icon: "star"))
        _ = ComposerRegistry.shared.all
        expectation.fulfill()
      }
    }

    wait(for: [expectation], timeout: 5)
    XCTAssertEqual(ComposerRegistry.shared.all.count, 100)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeClient && swift test --filter ComposerRegistryTests 2>&1 | head -20`
Expected: FAIL — `ComposerRegistry` not defined

**Step 3: Write the implementation**

Create `MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/ComposerRegistry.swift`:

```swift
import Foundation

/// Singleton registry for composer plugins.
///
/// Returns all registered plugins in registration order.
public final class ComposerRegistry: @unchecked Sendable {
  public static let shared = ComposerRegistry()
  private var plugins: [any ComposerPlugin] = []
  private let lock = NSLock()
  private init() {}

  public func register(_ plugin: any ComposerPlugin) {
    lock.lock()
    defer { lock.unlock() }
    plugins.append(plugin)
  }

  public func unregister(_ id: String) {
    lock.lock()
    defer { lock.unlock() }
    plugins.removeAll { $0.id == id }
  }

  public var all: [any ComposerPlugin] {
    lock.lock()
    defer { lock.unlock() }
    return plugins
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    plugins.removeAll()
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter ComposerRegistryTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/ComposerRegistry.swift \
  MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Composer/ComposerRegistryTests.swift
git commit -m "feat(client): add ComposerRegistry with tests"
```

---

### Task 4: SendButton View

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClient/Views/Composer/SendButton.swift`

**Step 1: Create the view**

```swift
import SwiftUI

/// Send button for the message composer.
///
/// Shows an arrow-up circle icon. Blue and enabled when content exists,
/// gray and disabled when empty.
struct SendButton: View {
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.up.circle.fill")
        .font(.title2)
    }
    .buttonStyle(.plain)
    .foregroundColor(enabled ? .blue : .secondary)
    .disabled(!enabled)
  }
}
```

**Step 2: Build to verify it compiles**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/Composer/SendButton.swift
git commit -m "feat(client): extract SendButton view"
```

---

### Task 5: ExpandingTextEditor View

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClient/Views/Composer/ExpandingTextEditor.swift`

**Step 1: Create the view**

```swift
import SwiftUI

/// A text editor that starts as a single line and expands up to `maxLines`,
/// then scrolls internally. Handles Enter (send) vs Shift+Enter (newline).
struct ExpandingTextEditor: View {
  @Binding var text: String
  var maxLines: Int = 6
  var placeholder: String = "Message"
  var onSubmit: (SubmitEvent) -> Void
  @FocusState private var isFocused: Bool

  var body: some View {
    ZStack(alignment: .topLeading) {
      if text.isEmpty {
        Text(placeholder)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 10)
          .allowsHitTesting(false)
      }

      TextEditor(text: $text)
        .scrollContentBackground(.hidden)
        .font(.body)
        .frame(minHeight: 36, maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .focused($isFocused)
        .onKeyPress(.return, phases: .down) { press in
          if press.modifiers.contains(.command) {
            onSubmit(.commandEnter)
            return .handled
          } else if press.modifiers.contains(.shift) {
            onSubmit(.shiftEnter)
            return .handled
          } else if press.modifiers.contains(.option) {
            onSubmit(.optionEnter)
            return .handled
          } else {
            onSubmit(.enter)
            return .handled
          }
        }
    }
    .padding(4)
    .background(RoundedRectangle(cornerRadius: 18).fill(.background))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.separator))
    .onAppear { isFocused = true }
  }

  private var maxHeight: CGFloat {
    CGFloat(maxLines) * 20 + 16
  }
}
```

**Step 2: Build to verify it compiles**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/Composer/ExpandingTextEditor.swift
git commit -m "feat(client): add ExpandingTextEditor view"
```

---

### Task 6: ComposerToolbar View

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClient/Views/Composer/ComposerToolbar.swift`

**Step 1: Create the view**

```swift
import MessageBridgeClientCore
import SwiftUI

/// Renders toolbar buttons for all registered composer plugins.
///
/// When no plugins are registered, renders nothing.
struct ComposerToolbar: View {
  let context: any ComposerContext

  var body: some View {
    let plugins = ComposerRegistry.shared.all.filter {
      $0.showsToolbarButton(context: context)
    }

    if !plugins.isEmpty {
      HStack(spacing: 4) {
        ForEach(plugins, id: \.id) { plugin in
          Button {
            Task { await plugin.activate(context: context) }
          } label: {
            Image(systemName: plugin.icon)
          }
          .buttonStyle(.borderless)
        }
      }
    }
  }
}
```

**Step 2: Build to verify it compiles**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/Composer/ComposerToolbar.swift
git commit -m "feat(client): add ComposerToolbar view"
```

---

### Task 7: ComposerView & Integration

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClient/Views/Composer/ComposerView.swift`
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift`

**Step 1: Create ComposerView**

```swift
import MessageBridgeClientCore
import SwiftUI

/// Main composer view replacing the old ComposeView.
///
/// Layout: [Toolbar] [ExpandingTextEditor] [SendButton]
struct ComposerView: View {
  @Binding var text: String
  let onSend: () -> Void

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      ComposerToolbar(context: composerContext)

      ExpandingTextEditor(
        text: $text,
        onSubmit: handleSubmit
      )

      SendButton(enabled: canSend) {
        onSend()
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  private var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func handleSubmit(_ event: SubmitEvent) {
    switch event {
    case .enter, .commandEnter:
      if canSend { onSend() }
    case .shiftEnter, .optionEnter:
      text += "\n"
    }
  }

  private var composerContext: LiveComposerContext {
    LiveComposerContext(text: $text, onSend: onSend)
  }
}

/// Concrete ComposerContext used by ComposerView to bridge plugins to SwiftUI state.
@MainActor
final class LiveComposerContext: ComposerContext {
  private var _text: Binding<String>
  private let _onSend: () -> Void
  var attachments: [DraftAttachment] = []
  private var sheetContent: AnyView?

  init(text: Binding<String>, onSend: @escaping () -> Void) {
    self._text = text
    self._onSend = onSend
  }

  var text: String {
    get { _text.wrappedValue }
    set { _text.wrappedValue = newValue }
  }

  func insertText(_ text: String) {
    self.text += text
  }

  func addAttachment(_ attachment: DraftAttachment) {
    attachments.append(attachment)
  }

  func removeAttachment(_ id: String) {
    attachments.removeAll { $0.id == id }
  }

  func presentSheet(_ view: AnyView) {
    sheetContent = view
  }

  func dismissSheet() {
    sheetContent = nil
  }

  func send() async {
    _onSend()
  }
}
```

**Step 2: Replace ComposeView in MessageThreadView**

In `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift`:

- Replace line 57 (`ComposeView(text: $messageText) {`) through line 59 (`}`) with:

```swift
      ComposerView(text: $messageText) {
        sendMessage()
      }
```

- Delete the entire `ComposeView` struct (lines 211-242).

**Step 3: Build to verify it compiles**

Run: `cd MessageBridgeClient && swift build`
Expected: Build succeeds

**Step 4: Run all tests**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/Composer/ComposerView.swift \
  MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift
git commit -m "feat(client): add ComposerView, replace ComposeView in MessageThreadView"
```

---

### Task 8: Register in App & Update Docs

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/App/MessageBridgeApp.swift`
- Modify: `CLAUDE.md`

**Step 1: Add setupComposer to app init**

In `MessageBridgeClient/Sources/MessageBridgeClient/App/MessageBridgeApp.swift`:

Add to `init()` after `setupActions()`:

```swift
    setupComposer()
```

Add the method after `setupRenderers()`:

```swift
  private func setupComposer() {
    // No plugins registered yet — infrastructure ready for future plugins
    _ = ComposerRegistry.shared
  }
```

**Step 2: Update CLAUDE.md migration table**

In `CLAUDE.md`, change the Client Composer row from:

```
| **Client Composer**     | Basic text field                              | `ComposerPlugin` protocol + expandable editor | 🔴 Not migrated    |
```

to:

```
| **Client Composer**     | ComposerPlugin + ExpandingTextEditor          | `ComposerPlugin` protocol + expandable editor | ✅ Migrated         |
```

**Step 3: Run full test suite**

Run: `cd MessageBridgeServer && swift test && cd ../MessageBridgeClient && swift test`
Expected: All tests PASS in both projects

**Step 4: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/App/MessageBridgeApp.swift CLAUDE.md
git commit -m "docs: mark Client Composer as migrated in CLAUDE.md"
```
