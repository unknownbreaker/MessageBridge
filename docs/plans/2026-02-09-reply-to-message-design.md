# Reply-to-Message Feature Design

## Summary

Add inline reply-to-message functionality, matching iMessage's native reply UX. Users can reply to specific messages with a compact quote bar showing the original message context, and send replies via UI automation through Messages.app.

## Scope

- **Display:** Show reply context (quoted message snippet + sender) above message bubbles via BubbleDecorator
- **Send:** Send replies via AppleScript UI automation (right-click message → Reply → type → send)
- **Compose:** Banner above composer showing reply context with cancel button

## Data Model Changes

### Server `Message` model

Add three optional fields sourced from chat.db columns:

```swift
public let replyToGuid: String?            // m.reply_to_guid — direct parent message GUID
public let threadOriginatorGuid: String?    // m.thread_originator_guid — root of thread
public let threadOriginatorPart: String?    // m.thread_originator_part — text snippet
```

### Client `Message` model

Mirror the same three fields.

### `SendMessageRequest`

Add optional field:

```swift
public let replyToGuid: String?  // GUID of message being replied to
```

### Database queries

Add `m.reply_to_guid`, `m.thread_originator_guid`, `m.thread_originator_part` to all message SELECT statements in `ChatDatabase`.

### WebSocket

No new message types needed. Reply fields flow through existing `new_message` → `ProcessedMessage` → `Message` pipeline.

## Server: Sending Replies via UI Automation

Since AppleScript's `send` command doesn't support reply-to, use accessibility UI scripting:

1. Navigate to the conversation in Messages.app
2. Find the target message bubble by text content in the accessibility tree
3. Right-click → "Reply" context menu item
4. Type reply text into the activated reply field
5. Press Return to send

### `AppleScriptMessageSender` additions

```swift
func sendReply(to messageGuid: String, text: String, in conversationId: String) async throws
```

### `/send` route changes

If `replyToGuid` is present in the request, call `sendReply()` instead of `sendMessage()`.

### Reliability

- Reuse existing retry + cooperative cancellation pattern
- Messages.app window must be accessible (not minimized)
- If target message not visible, may need to scroll/search
- Fallback: if reply-send fails, offer to send as regular message

## Client: Reply Quote Bar (BubbleDecorator)

New `ReplyPreviewDecorator` implementing `BubbleDecorator`:

- **Position:** `.topLeading` (above message bubble)
- **Condition:** `message.replyToGuid != nil` or `message.threadOriginatorGuid != nil`
- **Display:**
  - 2pt colored left border (accent for others, gray for own)
  - Sender name in bold (or "You")
  - Truncated original message text (1 line, ~80 chars)
- **Tap action:** Scroll to and highlight the original message

### Message resolution

Client-side lookup: search loaded messages by GUID. If the original message isn't loaded (too far back), show "Original message" as placeholder text.

## Client: Composer Reply Banner

### State

Add `replyingTo: Message?` to the conversation view model.

### Banner UI

- Appears above text field when `replyingTo` is set
- Shows sender name + truncated text + X cancel button
- Colored left border matching the quote bar style

### `ReplyAction` changes

Currently a stub showing an alert. Update `perform(on:)` to:

1. Set `replyingTo = message` on the view model
2. Focus the text field

### Send flow

When sending with `replyingTo` set:

1. Include `replyToGuid: replyingTo.guid` in `SendMessageRequest`
2. Clear `replyingTo` after successful send
3. Server receives `replyToGuid`, sends via UI automation

## Components Summary

| Component | Type | Location |
|-----------|------|----------|
| `Message` model update | Model | Server + Client |
| `SendMessageRequest` update | Model | Server |
| `ChatDatabase` query update | Database | Server |
| `AppleScriptMessageSender.sendReply()` | Messaging | Server |
| `/send` route update | API | Server |
| `ReplyPreviewDecorator` | BubbleDecorator | Client |
| Reply banner view | Composer UI | Client |
| `ReplyAction` update | MessageAction | Client |

## Testing

- Server: Unit tests for model serialization with reply fields
- Server: Unit tests for database query including reply columns
- Client: Unit tests for `ReplyPreviewDecorator` shouldDecorate logic
- Client: UI test for reply banner show/dismiss
- Integration: End-to-end reply send and display via WebSocket
