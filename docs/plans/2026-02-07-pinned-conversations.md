# Pinned Conversations Design

**Date:** 2026-02-07
**Status:** Draft

## Summary

Add two tiers of pinned conversations to the MessageBridgeClient sidebar:

1. **Messages Pins** (up to 9) — mirrors the pinned conversations in Messages.app, detected via accessibility. Displayed as regular list rows (not a grid) in the same order Messages.app shows them.
2. **Client Pins** (unlimited) — stored only in MessageBridgeClient. Managed via right-click context menu. Not reflected in Messages.app.

Both sections appear above the standard conversation list, which continues to sort by most recent message.

```
┌─────────────────────────┐
│ Messages Pins           │  ← Up to 9, mirrors Messages.app
│  Jamie                  │
│  Mom                    │
│  Family GC              │
├─────────────────────────┤
│ Client Pins             │  ← Unlimited, client-only
│  Work Group Chat        │
│  Carlos                 │
├─────────────────────────┤
│ (no header)             │  ← Everything else, sorted by recent
│  544487                 │
│  BTS GC                 │
│  ...                    │
└─────────────────────────┘
```

## Motivation

Messages.app limits pinned conversations to 9. For power users who want more, this adds a second tier that lives only in the bridge client. The first tier stays in sync with Messages.app so the two apps feel consistent.

## Server: Pin Detection

### PinnedConversationWatcher

A new component that polls Messages.app every 60 seconds via AppleScript accessibility. It reads the sidebar's `AXGenericElement` children within the "Conversations" group, filtering for descriptions containing `"Pinned"`. This is read-only — no clicks or keystrokes.

**Accessibility structure (macOS 26.2 Tahoe):**

```
AXGroup | Conversations
  AXGenericElement | Jamie, Pinned
  AXGenericElement | Mom, Pinned
  AXGenericElement | Family GC, Pinned
  AXGenericElement | Wang Sibs + Hubs, Unread, Pinned
  ...
  AXGenericElement | 544487, JCP&L OUTAGE ALERT: ..., 5:45 PM   ← not pinned
```

The element order in the sidebar is the pin order.

### Matching Display Names to Conversation IDs

The accessibility returns display names (e.g., "Mom", "Family GC"). The server must match these to `chat_identifier` values in `chat.db`.

| Case | Strategy |
|------|----------|
| **Group chats** | Match against `display_name` column in `chat` table (exact match) |
| **1:1 chats** | Match against the contact-resolved name the server already computes. The server resolves `+12013064677` → "Mom" via Contacts framework; reverse this lookup. |
| **Unresolved numbers/emails** | Match against `chat_identifier` directly (the pinned item shows the raw number/email) |

**Ambiguity:** If two conversations have the same resolved display name (unlikely in a set of 9), prefer the one with the most recent message.

### Caching

The matched result is stored in memory. The `/conversations` endpoint reads from cache — no AppleScript on each API request. If Messages.app is not running, the poll fails gracefully and the last known pinned list is preserved.

## API Changes

### `/conversations` Response

One new optional field per conversation:

```json
{
  "id": "chat677500401904448239",
  "displayName": "Family GC",
  "pinnedIndex": 4,
  ...
}
```

- `pinnedIndex`: `null` for unpinned, `0`–`8` for Messages.app pins (preserving sidebar order).
- No new endpoints. The server only knows about tier 1 pins.

### WebSocket

New message type broadcast when the pinned list changes (detected on 60-second poll):

```json
{
  "type": "pinned_conversations_changed",
  "data": {
    "pinned": [
      {"conversationId": "+12013064677", "index": 0},
      {"conversationId": "chat677500401904448239", "index": 1}
    ]
  }
}
```

## Client: Tier 2 Storage

Client-only pins stored as an ordered array of conversation IDs in UserDefaults:

```swift
@AppStorage("client.pinnedConversationIds")
var clientPinnedIds: [String] = []
```

## Client: Sidebar Sections

The view model computes three arrays from the flat conversation list:

1. **Messages Pins** — conversations where `pinnedIndex != nil`, sorted by `pinnedIndex`
2. **Client Pins** — conversations whose ID is in `clientPinnedIds`, sorted by array order
3. **Unpinned** — everything else, sorted by most recent message (existing behavior)

No duplicates: a conversation in tier 1 is excluded from tier 2 and unpinned. A conversation in tier 2 is excluded from unpinned.

### Section Headers

Small, muted headers styled like standard macOS sidebar section headers:
- **"Messages Pins"** — above tier 1
- **"Client Pins"** — above tier 2
- Unpinned section gets no header

### Context Menu

Every `ConversationRow` gets a right-click option:
- Not client-pinned → **"Pin to Client"** (appends to `clientPinnedIds`)
- Client-pinned → **"Unpin from Client"** (removes from `clientPinnedIds`)
- Messages.app pins don't show this option (managed in Messages.app itself)

### Search Behavior

When the search field is active, pinned sections collapse and all conversations filter as a flat list (existing behavior preserved).

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| New message on a pinned conversation | Stays at its pinned position; does not reorder. Only unpinned conversations reorder on new messages. |
| Messages.app pins change | Detected on next 60s poll, broadcast via WebSocket, client updates tier 1 in place. |
| Unpinned in Messages.app | Drops to unpinned section (unless also client-pinned, in which case it moves to tier 2). |
| Pinned conversation not in current page | Appears on next full refresh or individual fetch. |
| Messages.app not running | Poll fails gracefully; last known pinned list preserved in cache. |
| Reordering client pins | Not in v1. Pins maintain insertion order. Unpin and re-pin to reorder. |

## Out of Scope (v1)

- Drag-to-reorder client pins
- Pinning/unpinning in Messages.app from the bridge client
- Syncing client pins across multiple bridge clients
