# Tapback Display & Optimistic Send

**Date:** 2026-02-04
**Status:** Approved
**Milestone:** M4.1 Tapbacks (completion)

## Problem

Tapback infrastructure is 80% built but two gaps prevent usable reactions:

1. **TapbackPill never renders.** `MessageBubble` only renders `.below` and `.bottomTrailing` decorators. `TapbackDecorator` uses `.topTrailing`, so it's silently ignored.
2. **Sending has no visible effect.** The server endpoint returns `{success: true}` but doesn't bridge to Messages.app. No local state update occurs, so the user sees nothing after picking a tapback.

## Solution

### 1. Render `.topTrailing` Decorators

Add `.topTrailing` decorator rendering in the message bubble layout. The `TapbackPill` (capsule with grouped emojis + counts) will appear at the top-right of the bubble, offset to overlap the corner — matching macOS Messages.app style.

**File:** `MessageBubble.swift` or `MessageThreadView.swift` (wherever decorators are composed)

### 2. Optimistic Tapback Send

When the user picks a tapback from the context menu picker:

1. Client immediately updates local `message.tapbacks` state.
2. Client sends `POST /messages/:id/tapback` to server.
3. Server returns the tapback object in the response (not just `{success: true}`).
4. If the request fails, client rolls back to previous state and shows error toast.

**Behaviors:**
- **Toggle:** Tapping your existing emoji removes it (optimistic remove + remove request).
- **Switch:** Tapping a different emoji replaces yours (optimistic swap).
- **Rollback:** On server failure, revert local state and show toast.

**Files:**
- `MessagesViewModel.swift` — optimistic add/remove/rollback logic
- Server `Routes.swift` — return tapback data in response
- `BridgeConnection.swift` — decode richer tapback response

## Out of Scope

- AppleScript bridge to send tapbacks through Messages.app (future)
- Hover-to-reveal emoji bar (using context menu)
- Animated tapback appearance
- Tests (follow-up session)

## File Changes

| File | Change |
|------|--------|
| `MessageBubble.swift` / `MessageThreadView.swift` | Add `.topTrailing` decorator rendering |
| `MessagesViewModel.swift` | Optimistic tapback add/remove/rollback |
| Server `Routes.swift` | Return tapback object in response |
| `BridgeConnection.swift` | Decode richer tapback response |
