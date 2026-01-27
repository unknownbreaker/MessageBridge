# Client Actions Migration Design

## Overview

Migrate client message actions to the `MessageAction` protocol + `ActionRegistry` pattern, matching the existing protocol-driven architecture (renderers, decorators, attachment renderers).

## Protocol & Registry

### MessageAction Protocol (`Protocols/MessageAction.swift`)

```swift
public protocol MessageAction: Identifiable, Sendable {
    var id: String { get }
    var title: String { get }
    var icon: String { get }       // SF Symbol name
    var destructive: Bool { get }
    var keyboardShortcut: KeyboardShortcut? { get }

    func isAvailable(for message: Message) -> Bool
    @MainActor func perform(on message: Message) async
}
```

No ActionContext parameter. Actions use `NSPasteboard` directly for clipboard and post `Notification` for UI interactions.

### ActionRegistry (`Registries/ActionRegistry.swift`)

```swift
@MainActor
public final class ActionRegistry {
    public static let shared = ActionRegistry()
    private var actions: [any MessageAction] = []

    public func register(_ action: any MessageAction)
    public func availableActions(for message: Message) -> [any MessageAction]
}
```

Singleton, register at startup, query at use time. Same pattern as DecoratorRegistry and RendererRegistry.

### Action Notifications (`Actions/ActionNotifications.swift`)

Notification names for UI-triggering actions:

- `.beginReply` — Reply action
- `.showTapbackPicker` — Tapback action
- `.forwardMessage` — Forward action
- `.deleteMessage` — Delete action
- `.unsendMessage` — Unsend action
- `.shareMessage` — Share action
- `.translateMessage` — Translate action

Each notification passes the `Message` in `userInfo["message"]`.

## Action Implementations

All in `Sources/MessageBridgeClientCore/Actions/`:

| File | isAvailable | perform | destructive |
|------|-------------|---------|-------------|
| `CopyTextAction.swift` | `message.hasText` | Copies text to NSPasteboard | No |
| `CopyCodeAction.swift` | `message.detectedCodes?.isEmpty == false` | Copies first code to pasteboard | No |
| `ReplyAction.swift` | Always true | NSAlert stub + notification | No |
| `TapbackAction.swift` | Always true | NSAlert stub + notification | No |
| `ForwardAction.swift` | Always true | NSAlert stub + notification | No |
| `DeleteAction.swift` | `message.isFromMe` | NSAlert stub + notification | Yes |
| `UnsendAction.swift` | `message.isFromMe` | NSAlert stub + notification | Yes |
| `ShareAction.swift` | `message.hasText` | NSAlert stub + notification | No |
| `TranslateAction.swift` | `message.hasText` | NSAlert stub + notification | No |

Stub actions show an NSAlert with "Not Yet Implemented" message.

## Integration

### MessageBubble Context Menu

Add `.contextMenu` modifier to MessageBubble in `MessageThreadView.swift`:

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

### App Registration (`MessageBridgeApp.swift`)

New `setupActions()` method called from `init()`:

Registration order (determines menu order): Copy Text, Copy Code, Reply, Tapback, Forward, Share, Translate, Delete, Unsend.

## Tests

In `Tests/MessageBridgeClientCoreTests/Actions/`:

- `ActionRegistryTests.swift` — register, query available, ordering preserved
- `CopyTextActionTests.swift` — availability with/without text
- `CopyCodeActionTests.swift` — availability with/without detected codes
- `DeleteActionTests.swift` — only available for isFromMe
- `UnsendActionTests.swift` — only available for isFromMe

## Files Created

```
MessageBridgeClient/Sources/MessageBridgeClientCore/
├── Protocols/MessageAction.swift
├── Registries/ActionRegistry.swift
└── Actions/
    ├── ActionNotifications.swift
    ├── CopyTextAction.swift
    ├── CopyCodeAction.swift
    ├── ReplyAction.swift
    ├── TapbackAction.swift
    ├── ForwardAction.swift
    ├── DeleteAction.swift
    ├── UnsendAction.swift
    ├── ShareAction.swift
    └── TranslateAction.swift

MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Actions/
├── ActionRegistryTests.swift
├── CopyTextActionTests.swift
├── CopyCodeActionTests.swift
├── DeleteActionTests.swift
└── UnsendActionTests.swift
```

## Files Modified

- `MessageThreadView.swift` — Add `.contextMenu` to MessageBubble
- `MessageBridgeApp.swift` — Add `setupActions()` registration
- `CLAUDE.md` — Mark Client Actions as migrated
