# Client Actions Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add context menu actions to message bubbles using MessageAction protocol + ActionRegistry, matching existing protocol-driven architecture.

**Architecture:** Protocol (`MessageAction`) defines action interface. Singleton `ActionRegistry` collects all actions. `MessageBubble` queries registry to build `.contextMenu`. Actions use `NSPasteboard` for clipboard and `NotificationCenter` for UI triggers. Unimplemented actions show `NSAlert` stubs.

**Tech Stack:** Swift, SwiftUI, AppKit (NSPasteboard, NSAlert)

---

### Task 1: MessageAction Protocol

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/MessageAction.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Protocols/MessageActionTests.swift`
- Mock: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Mocks/MockMessageAction.swift`

**Step 1: Write the mock and test**

Create `Mocks/MockMessageAction.swift`:

```swift
import SwiftUI

@testable import MessageBridgeClientCore

final class MockMessageAction: MessageAction, @unchecked Sendable {
  let id: String
  let title: String
  let icon: String
  let destructive: Bool
  var isAvailableResult = true
  var performCallCount = 0

  init(
    id: String = "mock",
    title: String = "Mock",
    icon: String = "star",
    destructive: Bool = false
  ) {
    self.id = id
    self.title = title
    self.icon = icon
    self.destructive = destructive
  }

  func isAvailable(for message: Message) -> Bool {
    isAvailableResult
  }

  @MainActor
  func perform(on message: Message) async {
    performCallCount += 1
  }
}
```

Create `Protocols/MessageActionTests.swift`:

```swift
import XCTest

@testable import MessageBridgeClientCore

final class MessageActionTests: XCTestCase {
  func testConformsToIdentifiable() {
    let action = MockMessageAction(id: "test")
    XCTAssertEqual(action.id, "test")
  }

  func testProperties() {
    let action = MockMessageAction(id: "a", title: "Copy", icon: "doc.on.doc", destructive: false)
    XCTAssertEqual(action.title, "Copy")
    XCTAssertEqual(action.icon, "doc.on.doc")
    XCTAssertFalse(action.destructive)
  }

  func testDestructiveAction() {
    let action = MockMessageAction(id: "del", title: "Delete", icon: "trash", destructive: true)
    XCTAssertTrue(action.destructive)
  }

  func testIsAvailable() {
    let action = MockMessageAction()
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertTrue(action.isAvailable(for: msg))
    action.isAvailableResult = false
    XCTAssertFalse(action.isAvailable(for: msg))
  }
}
```

**Step 2: Run tests — expect FAIL (MessageAction protocol not found)**

Run: `cd MessageBridgeClient && swift test --filter MessageActionTests 2>&1 | tail -5`

**Step 3: Write protocol**

Create `Protocols/MessageAction.swift`:

```swift
import SwiftUI

/// Protocol for actions available on messages (context menu, keyboard shortcuts).
///
/// Unlike renderers which select ONE best match, ALL available actions
/// are shown in the context menu.
public protocol MessageAction: Identifiable, Sendable {
  var id: String { get }
  var title: String { get }
  var icon: String { get }
  var destructive: Bool { get }

  func isAvailable(for message: Message) -> Bool
  @MainActor func perform(on message: Message) async
}
```

**Step 4: Run tests — expect PASS**

Run: `cd MessageBridgeClient && swift test --filter MessageActionTests 2>&1 | tail -5`

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/MessageAction.swift \
  MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Protocols/MessageActionTests.swift \
  MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Mocks/MockMessageAction.swift
git commit -m "feat(client): add MessageAction protocol with tests"
```

---

### Task 2: ActionRegistry

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/ActionRegistry.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Registries/ActionRegistryTests.swift`

**Step 1: Write tests**

Create `Registries/ActionRegistryTests.swift`:

```swift
import XCTest

@testable import MessageBridgeClientCore

final class ActionRegistryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    ActionRegistry.shared.reset()
  }
  override func tearDown() {
    ActionRegistry.shared.reset()
    super.tearDown()
  }

  func testShared_isSingleton() {
    XCTAssertTrue(ActionRegistry.shared === ActionRegistry.shared)
  }

  func testRegister_addsAction() {
    ActionRegistry.shared.register(MockMessageAction(id: "a"))
    XCTAssertEqual(ActionRegistry.shared.all.count, 1)
  }

  func testReset_clears() {
    ActionRegistry.shared.register(MockMessageAction(id: "a"))
    ActionRegistry.shared.reset()
    XCTAssertTrue(ActionRegistry.shared.all.isEmpty)
  }

  func testAvailableActions_filtersUnavailable() {
    let available = MockMessageAction(id: "yes")
    let unavailable = MockMessageAction(id: "no")
    unavailable.isAvailableResult = false
    ActionRegistry.shared.register(available)
    ActionRegistry.shared.register(unavailable)
    let msg = makeMessage()
    let result = ActionRegistry.shared.availableActions(for: msg)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].id, "yes")
  }

  func testAvailableActions_preservesRegistrationOrder() {
    ActionRegistry.shared.register(MockMessageAction(id: "first"))
    ActionRegistry.shared.register(MockMessageAction(id: "second"))
    ActionRegistry.shared.register(MockMessageAction(id: "third"))
    let result = ActionRegistry.shared.availableActions(for: makeMessage())
    XCTAssertEqual(result.map { $0.id }, ["first", "second", "third"])
  }

  func testAvailableActions_emptyWhenNoneAvailable() {
    let action = MockMessageAction(id: "a")
    action.isAvailableResult = false
    ActionRegistry.shared.register(action)
    XCTAssertTrue(ActionRegistry.shared.availableActions(for: makeMessage()).isEmpty)
  }

  private func makeMessage() -> Message {
    Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
  }
}
```

**Step 2: Run tests — expect FAIL (ActionRegistry not found)**

Run: `cd MessageBridgeClient && swift test --filter ActionRegistryTests 2>&1 | tail -5`

**Step 3: Write registry**

Create `Registries/ActionRegistry.swift`:

```swift
import Foundation

/// Singleton registry for message actions.
///
/// Returns ALL available actions for a message in registration order.
public final class ActionRegistry: @unchecked Sendable {
  public static let shared = ActionRegistry()
  private var actions: [any MessageAction] = []
  private let lock = NSLock()
  private init() {}

  public func register(_ action: any MessageAction) {
    lock.lock()
    defer { lock.unlock() }
    actions.append(action)
  }

  public func availableActions(for message: Message) -> [any MessageAction] {
    lock.lock()
    defer { lock.unlock() }
    return actions.filter { $0.isAvailable(for: message) }
  }

  public var all: [any MessageAction] {
    lock.lock()
    defer { lock.unlock() }
    return actions
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    actions.removeAll()
  }
}
```

**Step 4: Run tests — expect PASS**

Run: `cd MessageBridgeClient && swift test --filter ActionRegistryTests 2>&1 | tail -5`

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/ActionRegistry.swift \
  MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Registries/ActionRegistryTests.swift
git commit -m "feat(client): add ActionRegistry with tests"
```

---

### Task 3: Action Notifications + CopyTextAction + CopyCodeAction

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/ActionNotifications.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/CopyTextAction.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/CopyCodeAction.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Actions/CopyTextActionTests.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Actions/CopyCodeActionTests.swift`

**Step 1: Write tests**

Create `Actions/CopyTextActionTests.swift`:

```swift
import XCTest

@testable import MessageBridgeClientCore

final class CopyTextActionTests: XCTestCase {
  let action = CopyTextAction()

  func testId() { XCTAssertEqual(action.id, "copy-text") }
  func testTitle() { XCTAssertEqual(action.title, "Copy") }
  func testIcon() { XCTAssertEqual(action.icon, "doc.on.doc") }
  func testNotDestructive() { XCTAssertFalse(action.destructive) }

  func testIsAvailable_withText_true() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertTrue(action.isAvailable(for: msg))
  }

  func testIsAvailable_nilText_false() {
    let msg = Message(
      id: 1, guid: "g1", text: nil, date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }

  func testIsAvailable_emptyText_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }
}
```

Create `Actions/CopyCodeActionTests.swift`:

```swift
import XCTest

@testable import MessageBridgeClientCore

final class CopyCodeActionTests: XCTestCase {
  let action = CopyCodeAction()

  func testId() { XCTAssertEqual(action.id, "copy-code") }
  func testTitle() { XCTAssertEqual(action.title, "Copy Code") }
  func testIcon() { XCTAssertEqual(action.icon, "number.square") }
  func testNotDestructive() { XCTAssertFalse(action.destructive) }

  func testIsAvailable_withCodes_true() {
    let code = DetectedCode(value: "123456", type: .numeric)
    let msg = Message(
      id: 1, guid: "g1", text: "Code: 123456", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1", detectedCodes: [code])
    XCTAssertTrue(action.isAvailable(for: msg))
  }

  func testIsAvailable_noCodes_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }

  func testIsAvailable_emptyCodes_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1", detectedCodes: [])
    XCTAssertFalse(action.isAvailable(for: msg))
  }
}
```

**Step 2: Run tests — expect FAIL**

Run: `cd MessageBridgeClient && swift test --filter "CopyTextActionTests|CopyCodeActionTests" 2>&1 | tail -5`

**Step 3: Write implementations**

Create `Actions/ActionNotifications.swift`:

```swift
import Foundation

extension Notification.Name {
  public static let beginReply = Notification.Name("messageAction.beginReply")
  public static let showTapbackPicker = Notification.Name("messageAction.showTapbackPicker")
  public static let forwardMessage = Notification.Name("messageAction.forwardMessage")
  public static let deleteMessage = Notification.Name("messageAction.deleteMessage")
  public static let unsendMessage = Notification.Name("messageAction.unsendMessage")
  public static let shareMessage = Notification.Name("messageAction.shareMessage")
  public static let translateMessage = Notification.Name("messageAction.translateMessage")
}
```

Create `Actions/CopyTextAction.swift`:

```swift
import AppKit

/// Copies message text to the clipboard.
public struct CopyTextAction: MessageAction {
  public let id = "copy-text"
  public let title = "Copy"
  public let icon = "doc.on.doc"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    message.hasText
  }

  @MainActor
  public func perform(on message: Message) async {
    guard let text = message.text else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
```

Create `Actions/CopyCodeAction.swift`:

```swift
import AppKit

/// Copies the first detected verification code to the clipboard.
public struct CopyCodeAction: MessageAction {
  public let id = "copy-code"
  public let title = "Copy Code"
  public let icon = "number.square"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    guard let codes = message.detectedCodes else { return false }
    return !codes.isEmpty
  }

  @MainActor
  public func perform(on message: Message) async {
    guard let code = message.detectedCodes?.first else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code.value, forType: .string)
  }
}
```

**Step 4: Run tests — expect PASS**

Run: `cd MessageBridgeClient && swift test --filter "CopyTextActionTests|CopyCodeActionTests" 2>&1 | tail -5`

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/ActionNotifications.swift \
  MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/CopyTextAction.swift \
  MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/CopyCodeAction.swift \
  MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Actions/CopyTextActionTests.swift \
  MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Actions/CopyCodeActionTests.swift
git commit -m "feat(client): add CopyTextAction, CopyCodeAction, and ActionNotifications"
```

---

### Task 4: Stub Actions (Reply, Tapback, Forward, Share, Translate, Delete, Unsend)

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/ReplyAction.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/TapbackAction.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/ForwardAction.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/ShareAction.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/TranslateAction.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/DeleteAction.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/UnsendAction.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Actions/DeleteActionTests.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Actions/UnsendActionTests.swift`

**Step 1: Write tests for gated actions**

Create `Actions/DeleteActionTests.swift`:

```swift
import XCTest

@testable import MessageBridgeClientCore

final class DeleteActionTests: XCTestCase {
  let action = DeleteAction()

  func testId() { XCTAssertEqual(action.id, "delete") }
  func testDestructive() { XCTAssertTrue(action.destructive) }

  func testIsAvailable_fromMe_true() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertTrue(action.isAvailable(for: msg))
  }

  func testIsAvailable_notFromMe_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }
}
```

Create `Actions/UnsendActionTests.swift`:

```swift
import XCTest

@testable import MessageBridgeClientCore

final class UnsendActionTests: XCTestCase {
  let action = UnsendAction()

  func testId() { XCTAssertEqual(action.id, "unsend") }
  func testDestructive() { XCTAssertTrue(action.destructive) }

  func testIsAvailable_fromMe_true() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
    XCTAssertTrue(action.isAvailable(for: msg))
  }

  func testIsAvailable_notFromMe_false() {
    let msg = Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: false, handleId: 1,
      conversationId: "c1")
    XCTAssertFalse(action.isAvailable(for: msg))
  }
}
```

**Step 2: Run tests — expect FAIL**

Run: `cd MessageBridgeClient && swift test --filter "DeleteActionTests|UnsendActionTests" 2>&1 | tail -5`

**Step 3: Write all stub actions**

Create `Actions/ReplyAction.swift`:

```swift
import AppKit

/// Reply to a message. Currently shows a stub alert.
public struct ReplyAction: MessageAction {
  public let id = "reply"
  public let title = "Reply"
  public let icon = "arrowshape.turn.up.left"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool { true }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
```

Create `Actions/TapbackAction.swift`:

```swift
import AppKit

/// Add a tapback reaction. Currently shows a stub alert.
public struct TapbackAction: MessageAction {
  public let id = "tapback"
  public let title = "Tapback"
  public let icon = "face.smiling"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool { true }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
```

Create `Actions/ForwardAction.swift`:

```swift
import AppKit

/// Forward a message. Currently shows a stub alert.
public struct ForwardAction: MessageAction {
  public let id = "forward"
  public let title = "Forward"
  public let icon = "arrowshape.turn.up.right"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool { true }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
```

Create `Actions/ShareAction.swift`:

```swift
import AppKit

/// Share message text via system share sheet. Currently shows a stub alert.
public struct ShareAction: MessageAction {
  public let id = "share"
  public let title = "Share"
  public let icon = "square.and.arrow.up"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    message.hasText
  }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
```

Create `Actions/TranslateAction.swift`:

```swift
import AppKit

/// Translate message text. Currently shows a stub alert.
public struct TranslateAction: MessageAction {
  public let id = "translate"
  public let title = "Translate"
  public let icon = "textformat"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    message.hasText
  }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
```

Create `Actions/DeleteAction.swift`:

```swift
import AppKit

/// Delete a sent message. Currently shows a stub alert.
public struct DeleteAction: MessageAction {
  public let id = "delete"
  public let title = "Delete"
  public let icon = "trash"
  public let destructive = true
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    message.isFromMe
  }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
```

Create `Actions/UnsendAction.swift`:

```swift
import AppKit

/// Unsend a recently sent message. Currently shows a stub alert.
public struct UnsendAction: MessageAction {
  public let id = "unsend"
  public let title = "Unsend"
  public let icon = "arrow.uturn.backward"
  public let destructive = true
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    message.isFromMe
  }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
```

Add shared stub helper to `ActionNotifications.swift` (append):

```swift
/// Shows a "not yet implemented" alert for stub actions.
@MainActor
func showStubAlert(title: String) {
  let alert = NSAlert()
  alert.messageText = "Not Yet Implemented"
  alert.informativeText = "\(title) will be available in a future update."
  alert.alertStyle = .informational
  alert.addButton(withTitle: "OK")
  alert.runModal()
}
```

**Step 4: Run tests — expect PASS**

Run: `cd MessageBridgeClient && swift test --filter "DeleteActionTests|UnsendActionTests" 2>&1 | tail -5`

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Actions/ \
  MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Actions/
git commit -m "feat(client): add stub actions (Reply, Tapback, Forward, Share, Translate, Delete, Unsend)"
```

---

### Task 5: Integrate into MessageBubble and App Registration

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift` (lines 101-152, MessageBubble struct)
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/App/MessageBridgeApp.swift` (lines 13-17, init + new method)

**Step 1: Add `.contextMenu` to MessageBubble**

In `MessageThreadView.swift`, wrap the existing `VStack` content inside `MessageBubble.body` (the one at line 115) with a `.contextMenu` modifier. Add it after the closing of the `VStack` at line 146 (after the below-decorators ForEach), before the closing of the outer `HStack`:

Add this modifier to the `VStack(alignment: ...)` block:

```swift
.contextMenu {
  ForEach(ActionRegistry.shared.availableActions(for: message)) { action in
    Button(role: action.destructive ? .destructive : nil) {
      Task { await action.perform(on: message) }
    } label: {
      Label(action.title, systemImage: action.icon)
    }
  }
}
```

**Step 2: Add setupActions() to MessageBridgeApp**

In `MessageBridgeApp.swift`, add call in `init()` after `setupDecorators()`:

```swift
init() {
  setupRenderers()
  setupAttachmentRenderers()
  setupDecorators()
  setupActions()
}
```

Add the new method:

```swift
private func setupActions() {
  let registry = ActionRegistry.shared
  registry.register(CopyTextAction())
  registry.register(CopyCodeAction())
  registry.register(ReplyAction())
  registry.register(TapbackAction())
  registry.register(ForwardAction())
  registry.register(ShareAction())
  registry.register(TranslateAction())
  registry.register(DeleteAction())
  registry.register(UnsendAction())
}
```

**Step 3: Build and run full test suite**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -10`

**Step 4: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift \
  MessageBridgeClient/Sources/MessageBridgeClient/App/MessageBridgeApp.swift
git commit -m "feat(client): integrate ActionRegistry into MessageBubble context menu"
```

---

### Task 6: Update CLAUDE.md + Full Verification

**Files:**
- Modify: `CLAUDE.md` — Change Client Actions status from 🔴 to ✅

**Step 1: Update migration table**

Change this line in the migration table:
```
| **Client Actions**    | Hardcoded context menu                        | `MessageAction` protocol + registry           | 🔴 Not migrated    |
```
To:
```
| **Client Actions**    | Context menu via ActionRegistry               | `MessageAction` protocol + registry           | ✅ Migrated         |
```

**Step 2: Run full test suite (both projects)**

Run: `cd MessageBridgeServer && swift test 2>&1 | tail -5 && cd ../MessageBridgeClient && swift test 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: mark Client Actions as migrated in CLAUDE.md"
```
