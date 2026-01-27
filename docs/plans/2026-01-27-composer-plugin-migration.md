# ComposerPlugin Migration Design

**Date:** 2026-01-27
**Scope:** Full composer overhaul — protocol, registry, expanding text editor, toolbar infrastructure

## Decisions

- Enter sends, Shift+Enter for newline (iMessage-style)
- Single-line default, expands up to 6 lines, then scrolls
- No concrete plugins in this pass — infrastructure only
- No draft attachment preview strip yet
- Full ComposerContext protocol defined upfront

## Protocol Definitions

### ComposerPlugin

```swift
public protocol ComposerPlugin: Identifiable, Sendable {
    var id: String { get }
    var icon: String { get }
    var keyboardShortcut: KeyEquivalent? { get }
    var modifiers: EventModifiers { get }

    func showsToolbarButton(context: any ComposerContext) -> Bool

    @MainActor func activate(context: any ComposerContext) async
}
```

### ComposerContext

```swift
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
```

### DraftAttachment

```swift
public struct DraftAttachment: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let type: AttachmentType
    public let fileName: String
}
```

## Registry

ComposerRegistry — singleton with NSLock, same pattern as ActionRegistry:

- `register(_ plugin:)`
- `unregister(_ id:)`
- `var all: [any ComposerPlugin]`

## Views

### ComposerView

Replaces current `ComposeView` in `MessageThreadView.swift`. Layout:

```
┌──────────────────────────────────────────┐
│ [Toolbar] [ExpandingTextEditor] [Send]   │
└──────────────────────────────────────────┘
```

- Toolbar renders buttons from `ComposerRegistry.shared.all`
- Toolbar renders nothing when no plugins registered
- Send button enabled when text is non-empty (trimmed)

### ExpandingTextEditor

- Starts as single line
- Grows as user types, up to 6 lines max
- Scrolls internally beyond 6 lines
- Shows placeholder "Message" when empty
- Key handling:
  - Enter → send
  - Shift+Enter → newline
  - Option+Enter → newline
  - Cmd+Enter → always send

### ComposerToolbar

Iterates `ComposerRegistry.shared.all`, renders a button per plugin that returns `showsToolbarButton == true`.

### SendButton

Extracted from current ComposeView. Enabled/disabled based on content.

## Files

### Create

```
MessageBridgeClientCore/Protocols/ComposerPlugin.swift
MessageBridgeClientCore/Registries/ComposerRegistry.swift
MessageBridgeClientCore/Models/DraftAttachment.swift

MessageBridgeClient/Views/Composer/ComposerView.swift
MessageBridgeClient/Views/Composer/ExpandingTextEditor.swift
MessageBridgeClient/Views/Composer/ComposerToolbar.swift
MessageBridgeClient/Views/Composer/SendButton.swift

Tests/MessageBridgeClientCoreTests/Composer/ComposerPluginTests.swift
Tests/MessageBridgeClientCoreTests/Composer/ComposerRegistryTests.swift
Tests/MessageBridgeClientCoreTests/Composer/ComposerContextTests.swift
```

### Modify

- `MessageThreadView.swift` — replace ComposeView with ComposerView
- `AppRegistration.swift` — add ComposerRegistry setup (empty)
- `CLAUDE.md` — mark Client Composer as migrated

## Testing

- Mock plugin conforming to ComposerPlugin, verify activate called
- Registry: register/unregister, thread safety, ordering
- Mock context: verify insertText, addAttachment, send delegation
- SubmitEvent handling: Enter sends, Shift+Enter inserts newline
