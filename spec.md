# MessageBridge Specification

This document defines **what** to build. See `CLAUDE.md` for **how** to build it.

---

## Overview

MessageBridge enables access to iMessages/SMS on a work Mac by relaying through a home Mac with iCloud.

**Components:**

- MessageBridgeServer (home Mac) - Reads Messages database, exposes API
- MessageBridgeClient (work Mac) - SwiftUI app connecting to server

---

## Milestones

### Status Key

- 🔴 Not Started
- 🟡 In Progress
- 🔵 Complete & Verified (tests pass, code reviewed)
- 🔵 Implemented (code exists, needs audit)
- ⏸️ Blocked

> **Refactor Note:** Features marked 🔵 were implemented in the original codebase but need to be:
>
> 1. Tested against spec (new tests, not existing ones)
> 2. Migrated to new architecture (protocols/registries)
> 3. Verified and marked 🔵

---

## Phase 1: Core Messaging 🔵

### M1.1: Basic Server 🔵

**User Stories:**

- Server reads conversations from Messages database
- Server exposes REST API for conversations and messages
- Server authenticates requests with API key

**Acceptance Criteria:**

- [ ] Reads from ~/Library/Messages/chat.db (read-only)
- [ ] GET /conversations returns paginated conversation list
- [ ] GET /conversations/:id/messages returns messages
- [ ] All endpoints require X-API-Key header
- [ ] Invalid API key returns 401

**Extension Point:** `API/Routes/`

---

### M1.2: Basic Client 🔵

**User Stories:**

- User can view list of conversations
- User can view messages in a conversation
- User can configure server connection

**Acceptance Criteria:**

- [ ] Conversation list shows contact name, last message preview, date
- [ ] Message thread shows bubbles with sent/received styling
- [ ] Settings screen for server URL and API key
- [ ] Credentials stored in Keychain

**Extension Point:** `Views/`, `ViewModels/`

---

### M1.3: Send Messages 🔵

**User Stories:**

- User can send text messages from client
- Server sends messages via Messages.app

**Acceptance Criteria:**

- [ ] Composer text field at bottom of message thread
- [ ] Enter sends message (configurable)
- [ ] POST /send endpoint accepts message
- [ ] Server uses AppleScript to send via Messages.app
- [ ] Sent message appears in thread immediately

**Extension Point:** `Messaging/AppleScriptSender.swift`

---

### M1.4: Real-time Updates 🔵

**User Stories:**

- New messages appear without refreshing
- User sees when messages are received in real-time

**Acceptance Criteria:**

- [ ] WebSocket connection at /ws
- [ ] Server watches chat.db for changes
- [ ] New messages pushed to connected clients
- [ ] Client reconnects automatically on disconnect

**Extension Point:** `API/Routes/WebSocketRoutes.swift`, `FileWatcher/`

---

## Phase 2: Connectivity 🔵

### M2.1: Tailscale Support 🔵

**User Stories:**

- User can connect via Tailscale VPN
- Server shows Tailscale IP in UI

**Acceptance Criteria:**

- [ ] Settings tab for Tailscale configuration
- [ ] Auto-detect Tailscale IP address
- [ ] Can set as default tunnel
- [ ] Status indicator in menu bar

**Extension Point:** `TunnelProvider` protocol, `Tunnels/Tailscale/`

---

### M2.2: Cloudflare Tunnel Support 🔵

**User Stories:**

- User can connect via Cloudflare Tunnel
- Works when VPNs are blocked

**Acceptance Criteria:**

- [ ] Settings tab for Cloudflare configuration
- [ ] Setup wizard for first-time configuration
- [ ] Manages cloudflared process
- [ ] Can set as default tunnel

**Extension Point:** `TunnelProvider` protocol, `Tunnels/Cloudflare/`

---

### M2.3: ngrok Support 🔵

**User Stories:**

- User can connect via ngrok for quick testing
- Simple setup with just auth token

**Acceptance Criteria:**

- [ ] Settings tab for ngrok configuration
- [ ] Enter auth token, optional custom domain
- [ ] Displays generated URL
- [ ] Can set as default tunnel

**Extension Point:** `TunnelProvider` protocol, `Tunnels/Ngrok/`

---

### M2.4: E2E Encryption 🔵

**User Stories:**

- Messages are encrypted end-to-end
- Third-party tunnels cannot read message content

**Acceptance Criteria:**

- [ ] AES-256-GCM encryption
- [ ] Key derived from API key via HKDF
- [ ] X-E2E-Encryption header enables encryption
- [ ] Required for Cloudflare/ngrok, optional for Tailscale

**Extension Point:** `Security/E2EEncryption.swift`

---

## Phase 3: Rich Messages 🟡

### M3.1: Attachments - Display 🟡

**User Stories:**

- User can view image attachments in messages
- User can view video attachments
- User can view file attachments

**Acceptance Criteria:**

- [ ] Images show as thumbnails in message bubble
- [ ] Tap thumbnail to open fullscreen
- [ ] Videos show thumbnail with play button
- [ ] Files show icon, name, and size
- [ ] Attachments download on demand

**Extension Point:** `AttachmentRenderer` protocol, `Renderers/Attachments/`

---

### M3.2: Image Gallery & Carousel 🔵

**User Stories:**

- Multiple images in one message show as grid
- User can swipe through images fullscreen

**Acceptance Criteria:**

- [ ] 2-4 images show as 2x2 grid
- [ ] 5+ images show as stack with count badge
- [ ] Tap opens carousel view
- [ ] Swipe left/right navigates images
- [ ] Pinch to zoom on individual images
- [ ] Page indicator shows position

**Extension Point:** `ImageGalleryRenderer`, `Views/Carousel/`

---

### M3.3: Attachments - Send 🔴

**User Stories:**

- User can attach files to messages
- User can attach photos from library
- User can take photo/video to send

**Acceptance Criteria:**

- [ ] Attachment button in composer toolbar
- [ ] Photo picker for library access
- [ ] Camera capture option
- [ ] Preview attachments before sending
- [ ] Remove attachment from draft
- [ ] Compress images before upload (configurable)

**Extension Point:** `ComposerPlugin` protocol, `Composer/AttachmentPickerPlugin.swift`

---

### M3.4: Audio Messages 🔴

**User Stories:**

- User can record and send voice messages
- User can play received audio messages

**Acceptance Criteria:**

- [ ] Microphone button in composer
- [ ] Hold to record, release to preview
- [ ] Waveform visualization during recording
- [ ] Play button on received audio
- [ ] Waveform shows playback progress
- [ ] Scrubber to seek within audio

**Extension Point:** `AudioRecorderPlugin`, `AudioRenderer`

---

## Phase 4: Reactions & Status 🟡

### M4.1: Tapbacks (Reactions) 🔵

**User Stories:**

- User can see tapbacks on messages
- User can add/remove tapbacks

**Acceptance Criteria:**

- [ ] Tapback pills appear above message bubble
- [ ] Shows emoji and count for each type
- [ ] Long-press message to add tapback
- [ ] Picker shows: ❤️ 👍 👎 😂 ‼️ ❓
- [ ] Tap existing tapback to remove
- [ ] Real-time sync via WebSocket

**Extension Point:** `BubbleDecorator` protocol, `Decorators/TapbackDecorator.swift`

---

### M4.2: Read Receipts 🔵

**User Stories:**

- User can see when messages are read
- User's read status syncs to sender

**Acceptance Criteria:**

- [ ] "Delivered" / "Read" status under sent messages
- [ ] Read timestamp on tap
- [ ] Mark conversation as read when viewed
- [ ] Sync read status via WebSocket

**Extension Point:** `BubbleDecorator` protocol, `Decorators/ReadReceiptDecorator.swift`

---

### M4.3: Typing Indicators 🔴

**User Stories:**

- User sees when others are typing
- Typing status sent while composing

**Acceptance Criteria:**

- [ ] "..." animation when contact is typing
- [ ] Appears in message thread, bottom
- [ ] Client sends typing status to server
- [ ] 5-second timeout without keystroke stops indicator

**Extension Point:** `PresenceProvider` protocol, `Presence/TypingIndicatorProvider.swift`

---

## Phase 5: Quality of Life 🔴

### M5.1: 2FA Code Detection 🔵

**User Stories:**

- Verification codes are highlighted
- One-tap copy code to clipboard

**Acceptance Criteria:**

- [ ] Detect 4-8 digit codes with context words
- [ ] Detect formatted codes (G-123456)
- [ ] Yellow highlight on detected codes
- [ ] "Copy [code]" button on message
- [ ] Optional: auto-copy high-confidence codes
- [ ] Notification when auto-copied

**Extension Point:** `MessageProcessor` protocol, `Processors/CodeDetector.swift`

---

### M5.2: Multi-line Composer 🔴

**User Stories:**

- User can write multi-line messages
- Composer expands as text grows

**Acceptance Criteria:**

- [ ] Text field grows up to 6 lines (configurable)
- [ ] Scrolls internally after max lines
- [ ] Shift+Enter or Option+Enter for newline
- [ ] Enter behavior configurable (send vs newline)
- [ ] Cmd+Enter always sends

**Extension Point:** `Views/Composer/ExpandingTextEditor.swift`

---

### M5.3: Text Selection 🔴

**User Stories:**

- User can select portions of message text
- User can copy selected text

**Acceptance Criteria:**

- [ ] Click and drag to select text in messages
- [ ] Right-click selection shows context menu
- [ ] Copy, Look Up, Share options
- [ ] Cmd+C copies selection

**Extension Point:** `Renderers/Messages/SelectableMessageText.swift`

---

### M5.4: Link Previews 🔴

**User Stories:**

- URLs in messages show rich previews
- Preview shows title, description, image

**Acceptance Criteria:**

- [ ] Detect URLs in message text
- [ ] Fetch metadata (title, description, image)
- [ ] Display card below message text
- [ ] Tap card opens URL in browser
- [ ] Cache previews to avoid re-fetching

**Extension Point:** `MessageProcessor` for detection, `MessageRenderer` for display

---

### M5.5: Search 🔵

**User Stories:**

- User can search across all messages
- Search results link to conversation

**Acceptance Criteria:**

- [ ] Search bar in conversation list
- [ ] GET /search?q= endpoint
- [ ] Results show message snippet and conversation
- [ ] Tap result navigates to message in thread

**Extension Point:** `API/Routes/SearchRoutes.swift`

---

## Phase 6: Polish 🔴

### M6.1: Contact Names 🔵

**User Stories:**

- Phone numbers show contact names
- Contact photos display in conversation list

**Acceptance Criteria:**

- [ ] Resolve phone/email to contact name
- [ ] Show contact photo as avatar
- [ ] Fallback to initials if no photo
- [ ] Cache contact lookups

---

### M6.2: Notifications 🔵

**User Stories:**

- New messages trigger system notification
- Clicking notification opens conversation

**Acceptance Criteria:**

- [ ] macOS notification for new messages
- [ ] Shows sender name and message preview
- [ ] Click opens app to that conversation
- [ ] No notification if app is active and conversation visible

---

### M6.3: Dark Mode 🔴

**User Stories:**

- App respects system appearance
- Message bubbles readable in both modes

**Acceptance Criteria:**

- [ ] Follows system light/dark setting
- [ ] Sent bubbles: blue in both modes
- [ ] Received bubbles: gray (light) / dark gray (dark)
- [ ] Text contrast meets accessibility guidelines

---

### M6.4: Keyboard Navigation 🔴

**User Stories:**

- User can navigate entirely by keyboard
- Shortcuts for common actions

**Acceptance Criteria:**

- [ ] Tab through conversations
- [ ] Arrow keys in message list
- [ ] Cmd+F focuses search
- [ ] Cmd+N new conversation (future)
- [ ] Escape clears selection / closes modals

---

## Future Considerations

These are not planned but may be added later:

- **Group chat support** - Display and send to group conversations
- **Message threading** - Reply to specific messages
- **Stickers and effects** - Display/send iMessage effects
- **Message editing** - Edit sent messages (iOS 16+)
- **Undo send** - Unsend recent messages (iOS 16+)
- **Schedule send** - Send messages at specific time
- **Quick replies** - Suggested responses based on context
- **Multiple accounts** - Connect to multiple servers

---

## Changelog

| Date       | Change                                        |
| ---------- | --------------------------------------------- |
| 2024-01-15 | Initial spec with Phase 1-2                   |
| 2024-02-01 | Added Phase 3-6 milestones                    |
| 2024-03-01 | Added 2FA code detection, multi-line composer |
