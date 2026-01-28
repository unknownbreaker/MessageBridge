# M3.1 Attachments Display — Audit Design

**Goal:** Write blind audit tests for all 5 M3.1 acceptance criteria, run them, document findings.

## Acceptance Criteria (from spec.md)

1. Images show as thumbnails in message bubble
2. Tap thumbnail to open fullscreen
3. Videos show thumbnail with play button
4. Files show icon, name, and size
5. Attachments download on demand

## Test Approach

Single file: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Audit/M3_1_AttachmentsDisplayAuditTests.swift`

**AC1 — Image thumbnails:** Verify `SingleImageRenderer.canRender` returns true for image attachments, and `ImageGalleryRenderer.canRender` for 2+ images. Verify registry selects image renderer over document fallback.

**AC2 — Tap to fullscreen:** Structural test — verify `SingleImageRenderer` exists with correct priority. Full tap behavior is UI-level, not unit-testable.

**AC3 — Video thumbnail + play:** Verify `VideoRenderer.canRender` returns true for video attachments and false for non-video.

**AC4 — File icon/name/size:** Verify `DocumentRenderer.canRender` returns true as fallback. Verify `Attachment.formattedSize` and `filename` are accessible.

**AC5 — Download on demand:** Verify `BridgeConnection` has `fetchAttachment(id:)` method signature. Verify `Attachment.thumbnailData` decodes base64.

## Expected Results

All tests should pass — renderers and models already exist. This audit confirms spec compliance and documents any gaps.
