# Conversation Reorder on New Message

**Date:** 2026-02-07
**Status:** Approved

## Summary

Move conversations to the top of the sidebar when they receive a new message, matching Messages.app behavior.

## Behavior

- Any new message (incoming or outgoing) moves that conversation to position 0 in the sidebar list
- Applies to both WebSocket-delivered messages and confirmed sent messages
- Initial load from server already returns conversations sorted by last message date (no change needed)
- SwiftUI List handles the visual reorder animation automatically

## Implementation

**File:** `MessagesViewModel.swift` — `handleNewMessage()` method

Change the in-place update to a remove-and-insert-at-top:

```swift
// Before:
newConversations[index] = updatedConversation

// After:
newConversations.remove(at: index)
newConversations.insert(updatedConversation, at: 0)
```

**No server changes needed.** The server already sorts by `message.date DESC` on initial fetch.

## Edge Cases

- Conversation already at index 0: remove + insert at 0 = no visual change
- Selected conversation receives message: `selectedConversationId` is tracked by ID (not index), so selection is preserved
- Conversation not in list: existing "not found" code path handles this (no change)

## Testing

One new test: set up conversations [A, B, C], simulate message for C, assert order is [C, A, B].
