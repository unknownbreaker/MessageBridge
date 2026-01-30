# Infinite Scroll for Message Loading

**Date:** 2026-01-29
**Status:** Approved
**Scope:** Client-only (server already supports pagination)

## Problem

Opening conversations with many messages is slow because the client loads 50 messages in a single request with no way to load more. Users experience both a sluggish initial load and inability to access older messages.

## Solution

Reverse-chronological infinite scroll: load the most recent 30 messages on open, then fetch older batches of 30 as the user scrolls up.

## Design

### Pagination State

Add per-conversation pagination tracking to `MessagesViewModel`:

```swift
struct PaginationState {
    var offset: Int = 0
    var hasMore: Bool = true
    var isLoadingMore: Bool = false
}

var paginationState: [String: PaginationState] = [:]
```

### ViewModel Changes

**`loadMessages(for:)`** — reset pagination, fetch first 30, set `offset = 30`, derive `hasMore` from `nextCursor`.

**`loadMoreMessages(for:)`** — guard `!isLoadingMore && hasMore`, fetch next 30 at current offset, prepend to messages array, increment offset.

No changes to `BridgeConnection.fetchMessages(conversationId:limit:offset:)` — it already accepts these parameters.

### View Changes (MessageThreadView)

Add a sentinel view and spinner at the top of the message list:

- Invisible `Color.clear` sentinel with `onAppear` trigger when `hasMore` is true
- `ProgressView` spinner when `isLoadingMore` is true
- "Failed to load. Tap to retry" inline banner on error

**Scroll position preservation:** Capture the top-visible message ID before prepending, then use `ScrollViewReader` to re-anchor after load.

### Error Handling

- Network failure: show inline retry banner, keep offset unchanged
- Duplicate messages: skip by ID during prepend
- Conversation switch: reset pagination state (existing behavior)

### Not In Scope (YAGNI)

- Memory eviction of old messages
- Cursor-based pagination (offset is fine for read-only historical data)
- Prefetching the next page before scroll trigger

## Files Changed

| File | Change |
|------|--------|
| `MessagesViewModel.swift` | Add `PaginationState`, update `loadMessages`, add `loadMoreMessages` |
| `MessageThreadView.swift` | Add scroll trigger sentinel, spinner, retry banner, scroll anchoring |

## Batch Size

- Initial load: 30 messages
- Subsequent loads: 30 messages
- Scroll trigger: sentinel view at top of list (fires via `onAppear`)
