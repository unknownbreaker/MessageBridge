# Unified Highlight Rendering — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make all server-side enrichments (detected codes, phone numbers, mentions) render on the client, including real-time WebSocket messages.

**Architecture:** Single `HighlightedTextRenderer` replaces `CodeHighlightRenderer`. Uses server-provided `highlights` array with character offsets to style text. Retains copy-code button for detected codes. WebSocket payloads extended to carry enrichment fields.

**Tech Stack:** Swift, SwiftUI, AttributedString

---

### Task 1: Add `mentions` to Client Message Model

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/Models.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Models/MessageDecodingTests.swift` (create if needed)

**What:** Add `let mentions: [Mention]?` to the `Message` struct. Verify `Mention` model already exists on the client. Add a decoding test that JSON with/without mentions decodes correctly.

**TDD:**
1. Write test: decode JSON with `mentions` field → expect non-nil
2. Write test: decode JSON without `mentions` → expect nil
3. Run tests — expect FAIL
4. Add field to Message
5. Run tests — expect PASS
6. Commit: `feat(client): add mentions field to Message model`

---

### Task 2: Extend WebSocket NewMessageData with Enrichments

**Files:**
- Modify (server): `MessageBridgeServer/Sources/MessageBridgeCore/API/WebSocketManager.swift`
- Modify (server): `MessageBridgeServer/Sources/MessageBridgeCore/Models/WebSocketMessage.swift` (or wherever NewMessageData lives)
- Modify (client): `MessageBridgeClient/Sources/MessageBridgeClientCore/Services/BridgeConnection.swift` (or wherever WebSocket messages are decoded)
- Test (server): `MessageBridgeServer/Tests/MessageBridgeCoreTests/API/WebSocketManagerTests.swift`
- Test (client): `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Services/WebSocketDecodingTests.swift` (create if needed)

**What:**
- Server: Add `detectedCodes`, `highlights`, `mentions`, `isEmojiOnly` to `NewMessageData` struct. Populate from `ProcessedMessage` in `broadcastNewMessage()`.
- Client: Update decoder to read enrichment fields from WebSocket JSON and pass them into `Message`.

**TDD:**
1. Write server test: broadcast a ProcessedMessage with codes → NewMessageData JSON contains `detectedCodes`
2. Write client test: decode WebSocket JSON with enrichment fields → Message has them populated
3. Run tests — expect FAIL
4. Implement server + client changes
5. Run tests — expect PASS
6. Commit: `feat: extend WebSocket NewMessageData with enrichment fields`

---

### Task 3: HighlightedTextRenderer

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/HighlightedTextRenderer.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/HighlightedTextView.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/HighlightedTextRendererTests.swift`

**What:**
- Priority 90 (above PlainText at 0, below LinkPreview at 100)
- `canRender`: `message.highlights` is non-nil and non-empty
- `render`: builds `AttributedString` using `TextHighlight.startIndex`/`endIndex` offsets
  - `.code` → yellow background, monospace font
  - `.phoneNumber` → blue foreground
  - `.mention` → bold, accent color
- If `message.detectedCodes` is non-empty, shows copy-code button (same UX as current CodeHighlightRenderer)

**TDD:**
1. Write test: `canRender` returns true when highlights present
2. Write test: `canRender` returns false when highlights nil/empty
3. Write test: renderer has priority 90
4. Write test: renderer id is "highlighted-text"
5. Run tests — expect FAIL
6. Implement renderer + view
7. Run tests — expect PASS
8. Commit: `feat(client): add HighlightedTextRenderer for unified enrichment display`

---

### Task 4: Retire CodeHighlightRenderer, Register New Renderer

**Files:**
- Delete: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/CodeHighlightRenderer.swift`
- Delete or adapt: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/CodeHighlightRendererTests.swift`
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/App/MessageBridgeApp.swift` — replace `CodeHighlightRenderer` registration with `HighlightedTextRenderer`

**What:**
- Remove CodeHighlightRenderer source file
- Update `setupRenderers()` to register `HighlightedTextRenderer()` instead
- Adapt existing CodeHighlightRenderer tests to cover HighlightedTextRenderer (same scenarios: code detection, copy button)
- Run full client test suite

**TDD:**
1. Update tests to reference HighlightedTextRenderer
2. Remove old source
3. Update registration
4. Run full test suite — expect PASS
5. Commit: `refactor(client): replace CodeHighlightRenderer with HighlightedTextRenderer`

---

### Task 5: Full Verification + CLAUDE.md Update

**What:**
- Run both server and client test suites
- Update CLAUDE.md "Current Focus" / "Next Steps" to reflect completed work
- Commit: `docs: update CLAUDE.md after unified highlight rendering`
