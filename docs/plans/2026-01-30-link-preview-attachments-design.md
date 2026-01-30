# Link Preview & Attachment Filtering Design

**Date:** 2026-01-30
**Status:** Approved

## Problem

iMessage stores URL rich link preview data as attachments in `chat.db` — files named like `pluginPayloadAttachment-<UUID>`. The server returns these as regular attachments with no filtering, so the client renders them as document icons with UUID filenames, cluttering conversations.

## Scope

### In Scope
1. **Server-side filtering** — exclude link preview attachments, stickers, and zero-byte attachments
2. **Server-side extraction** — decode `LPLinkMetadata` from `message.payload_data` blob
3. **Client-side rendering** — iMessage-style full-width link preview cards using server-provided metadata

### Out of Scope
- Client-side URL fetching (replaced by server-provided data)
- Video/audio preview playback improvements
- Sticker rendering (filtered out now, future feature)

## Design

### Server: Filter Junk Attachments

Modify `fetchAttachmentsForMessage` in `ChatDatabase.swift` to exclude:
- Attachments where `transfer_name` contains `pluginPayloadAttachment`
- Attachments where `is_sticker = 1`
- Attachments where `total_bytes = 0`

### Server: Extract Link Metadata

In `fetchMessagesFromDB`, when `balloon_bundle_id = 'com.apple.messages.URLBalloonProvider'`:
- Read `payload_data` column
- Decode with `NSKeyedUnarchiver` (requiresSecureCoding = false) into `LPLinkMetadata`
- Extract: URL, title, summary, site name
- For the preview image: find the `.pluginPayloadAttachment` before filtering, generate thumbnail, include as base64

New model field on server `Message`:
```swift
struct LinkPreview: Codable, Sendable {
    let url: String
    let title: String?
    let summary: String?
    let siteName: String?
    let imageBase64: String?
}
```

If decoding fails, silently skip — the URL text remains in the message.

### Client: Model Update

Add matching `LinkPreview` struct and `linkPreview: LinkPreview?` to client `Message` model.

### Client: LinkPreviewRenderer Update

Replace client-side URL fetching with server-provided metadata. Render iMessage-style card:

```
┌─────────────────────────────┐
│                             │
│     (preview image)         │
│     from imageBase64        │
│                             │
├─────────────────────────────┤
│ Title                       │
│ summary (2 lines max)       │
│ 🔗 domain.com              │
└─────────────────────────────┘
```

- Image fills card width, aspect-fit, max height ~200pt
- No image area if `imageBase64` is nil
- Card max width ~280pt, rounded corners (12pt), subtle border/shadow
- Tap opens URL in default browser
- `canRender` checks `message.linkPreview != nil`
- Priority stays at 100

### Client: Cleanup

Simplify or remove `LinkPreviewCache` — no longer needed for client-side fetching.

## Implementation Order

Each step is independently shippable.

1. **Server: filter junk attachments** — messages with links stop returning ghost attachments
2. **Server: extract link preview data** — add `balloon_bundle_id`/`payload_data` to query, decode `LPLinkMetadata`, add `LinkPreview` to `Message` model
3. **Client: model update** — add `LinkPreview` struct, `linkPreview` field on `Message`
4. **Client: update LinkPreviewRenderer** — render iMessage-style card from `message.linkPreview`, remove client-side URL fetching
5. **Client: cleanup** — simplify/remove `LinkPreviewCache`, verify no regressions

## Testing

- Server: messages with URLs return populated `linkPreview` field and no ghost attachments
- Server: messages without URLs are unaffected
- Server: corrupted `payload_data` fails gracefully (no crash, no preview)
- Client: `LinkPreview` deserializes correctly from server JSON
- Client: card renders with image, title, domain
- Client: card renders without image when `imageBase64` is nil
- Client: tap opens URL in browser
- Client: regular image/video/document attachments still work
