# Link Preview & Attachment Filtering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Filter junk attachments (link previews, stickers, zero-byte) from the message feed and render rich link preview cards using metadata Apple already stored in chat.db.

**Architecture:** Server-side filtering in `fetchAttachmentsForMessage` excludes ghost attachments. Server decodes `LPLinkMetadata` from `message.payload_data` and sends structured `LinkPreview` data to the client. Client renders iMessage-style cards.

**Tech Stack:** GRDB (server DB), NSKeyedUnarchiver + LinkPresentation (metadata decoding), SwiftUI (client card rendering)

---

### Task 1: Server — Filter Junk Attachments

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift:562-613` (fetchAttachmentsForMessage)
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/AttachmentFilteringTests.swift` (create)

**Step 1: Write the failing test**

Create `MessageBridgeServer/Tests/MessageBridgeCoreTests/AttachmentFilteringTests.swift`:

```swift
import XCTest

@testable import MessageBridgeCore

final class AttachmentFilteringTests: XCTestCase {

  // MARK: - Attachment.shouldFilter Tests

  func testShouldFilter_pluginPayloadAttachment_returnsTrue() {
    let attachment = Attachment(
      id: 1, guid: "g1",
      filename: "pluginPayloadAttachment-7A3B2C1D-E4F5-6789-ABCD-EF0123456789",
      mimeType: nil, uti: nil, size: 1024,
      isOutgoing: false, isSticker: false
    )
    XCTAssertTrue(attachment.shouldFilter)
  }

  func testShouldFilter_sticker_returnsTrue() {
    let attachment = Attachment(
      id: 2, guid: "g2",
      filename: "sticker.png",
      mimeType: "image/png", uti: nil, size: 50000,
      isOutgoing: false, isSticker: true
    )
    XCTAssertTrue(attachment.shouldFilter)
  }

  func testShouldFilter_zeroBytes_returnsTrue() {
    let attachment = Attachment(
      id: 3, guid: "g3",
      filename: "empty.dat",
      mimeType: nil, uti: nil, size: 0,
      isOutgoing: false, isSticker: false
    )
    XCTAssertTrue(attachment.shouldFilter)
  }

  func testShouldFilter_normalImage_returnsFalse() {
    let attachment = Attachment(
      id: 4, guid: "g4",
      filename: "photo.jpg",
      mimeType: "image/jpeg", uti: nil, size: 150000,
      isOutgoing: false, isSticker: false
    )
    XCTAssertFalse(attachment.shouldFilter)
  }

  func testShouldFilter_normalDocument_returnsFalse() {
    let attachment = Attachment(
      id: 5, guid: "g5",
      filename: "report.pdf",
      mimeType: "application/pdf", uti: nil, size: 200000,
      isOutgoing: false, isSticker: false
    )
    XCTAssertFalse(attachment.shouldFilter)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter AttachmentFilteringTests 2>&1 | tail -20`
Expected: FAIL — `shouldFilter` property doesn't exist yet

**Step 3: Write minimal implementation**

Add `shouldFilter` computed property to `MessageBridgeServer/Sources/MessageBridgeCore/Models/Attachment.swift`:

```swift
/// Whether this attachment should be filtered from display.
/// Filters: link preview payloads, stickers, zero-byte ghosts.
public var shouldFilter: Bool {
  if isSticker { return true }
  if size <= 0 { return true }
  if filename.contains("pluginPayloadAttachment") { return true }
  return false
}
```

**Step 4: Apply filter in ChatDatabase**

In `ChatDatabase.swift`, change the return in `fetchAttachmentsForMessage` (line ~583) from:

```swift
return rows.compactMap { row -> Attachment? in
```

to filter at the end:

```swift
return rows.compactMap { row -> Attachment? in
    // ... existing mapping code ...
}.filter { !$0.shouldFilter }
```

**Step 5: Run tests to verify they pass**

Run: `cd MessageBridgeServer && swift test --filter AttachmentFilteringTests 2>&1 | tail -20`
Expected: All 5 tests PASS

**Step 6: Run full server test suite**

Run: `cd MessageBridgeServer && swift test 2>&1 | tail -20`
Expected: All tests pass (no regressions)

**Step 7: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Models/Attachment.swift \
       MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift \
       MessageBridgeServer/Tests/MessageBridgeCoreTests/AttachmentFilteringTests.swift
git commit -m "feat(server): filter junk attachments (link previews, stickers, zero-byte)"
```

---

### Task 2: Server — Add LinkPreview Model

**Files:**
- Create: `MessageBridgeServer/Sources/MessageBridgeCore/Models/LinkPreview.swift`
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Models/Message.swift`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/LinkPreviewTests.swift` (create)

**Step 1: Write the failing test**

Create `MessageBridgeServer/Tests/MessageBridgeCoreTests/LinkPreviewTests.swift`:

```swift
import XCTest

@testable import MessageBridgeCore

final class LinkPreviewTests: XCTestCase {

  func testLinkPreview_encodesAndDecodes() throws {
    let preview = LinkPreview(
      url: "https://apple.com",
      title: "Apple",
      summary: "Apple leads the world in innovation.",
      siteName: "Apple",
      imageBase64: "base64data"
    )

    let data = try JSONEncoder().encode(preview)
    let decoded = try JSONDecoder().decode(LinkPreview.self, from: data)

    XCTAssertEqual(decoded.url, "https://apple.com")
    XCTAssertEqual(decoded.title, "Apple")
    XCTAssertEqual(decoded.summary, "Apple leads the world in innovation.")
    XCTAssertEqual(decoded.siteName, "Apple")
    XCTAssertEqual(decoded.imageBase64, "base64data")
  }

  func testLinkPreview_decodesWithNilOptionals() throws {
    let json = """
      {"url": "https://example.com"}
      """
    let decoded = try JSONDecoder().decode(LinkPreview.self, from: json.data(using: .utf8)!)

    XCTAssertEqual(decoded.url, "https://example.com")
    XCTAssertNil(decoded.title)
    XCTAssertNil(decoded.summary)
    XCTAssertNil(decoded.siteName)
    XCTAssertNil(decoded.imageBase64)
  }

  func testMessage_withLinkPreview_encodesAndDecodes() throws {
    let preview = LinkPreview(
      url: "https://apple.com",
      title: "Apple",
      summary: nil,
      siteName: "Apple",
      imageBase64: nil
    )

    let message = Message(
      id: 1, guid: "g1", text: "https://apple.com",
      date: Date(timeIntervalSinceReferenceDate: 0),
      isFromMe: true, handleId: nil,
      conversationId: "c1",
      linkPreview: preview
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = try encoder.encode(message)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(Message.self, from: data)

    XCTAssertEqual(decoded.linkPreview?.url, "https://apple.com")
    XCTAssertEqual(decoded.linkPreview?.title, "Apple")
    XCTAssertEqual(decoded.linkPreview?.siteName, "Apple")
  }

  func testMessage_withoutLinkPreview_decodesNil() throws {
    let message = Message(
      id: 1, guid: "g1", text: "Hello",
      date: Date(timeIntervalSinceReferenceDate: 0),
      isFromMe: true, handleId: nil,
      conversationId: "c1"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = try encoder.encode(message)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(Message.self, from: data)

    XCTAssertNil(decoded.linkPreview)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter LinkPreviewTests 2>&1 | tail -20`
Expected: FAIL — `LinkPreview` type doesn't exist

**Step 3: Create LinkPreview model**

Create `MessageBridgeServer/Sources/MessageBridgeCore/Models/LinkPreview.swift`:

```swift
import Foundation
import Vapor

/// Rich link preview metadata extracted from iMessage's payload_data
public struct LinkPreview: Content, Sendable {
  public let url: String
  public let title: String?
  public let summary: String?
  public let siteName: String?
  public let imageBase64: String?

  public init(
    url: String,
    title: String? = nil,
    summary: String? = nil,
    siteName: String? = nil,
    imageBase64: String? = nil
  ) {
    self.url = url
    self.title = title
    self.summary = summary
    self.siteName = siteName
    self.imageBase64 = imageBase64
  }
}
```

**Step 4: Add linkPreview to server Message**

In `MessageBridgeServer/Sources/MessageBridgeCore/Models/Message.swift`, add:

```swift
public var linkPreview: LinkPreview?
```

Update the `init` to include `linkPreview: LinkPreview? = nil` parameter and assign it.

**Step 5: Run tests to verify they pass**

Run: `cd MessageBridgeServer && swift test --filter LinkPreviewTests 2>&1 | tail -20`
Expected: All 4 tests PASS

**Step 6: Run full server test suite**

Run: `cd MessageBridgeServer && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 7: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Models/LinkPreview.swift \
       MessageBridgeServer/Sources/MessageBridgeCore/Models/Message.swift \
       MessageBridgeServer/Tests/MessageBridgeCoreTests/LinkPreviewTests.swift
git commit -m "feat(server): add LinkPreview model to Message"
```

---

### Task 3: Server — Extract LPLinkMetadata from payload_data

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift:169-225` (fetchMessagesFromDB)
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/LinkPreviewExtractionTests.swift` (create)

**Step 1: Write the failing test**

Create `MessageBridgeServer/Tests/MessageBridgeCoreTests/LinkPreviewExtractionTests.swift`:

```swift
import XCTest
import LinkPresentation

@testable import MessageBridgeCore

final class LinkPreviewExtractionTests: XCTestCase {

  // Test the extraction helper directly
  func testExtractLinkPreview_withValidMetadata_returnsPreview() throws {
    // Create a real LPLinkMetadata and archive it
    let metadata = LPLinkMetadata()
    metadata.url = URL(string: "https://apple.com")!
    metadata.title = "Apple"

    let data = try NSKeyedArchiver.archivedData(
      withRootObject: metadata, requiringSecureCoding: false
    )

    let preview = LinkPreviewExtractor.extract(from: data)
    XCTAssertNotNil(preview)
    XCTAssertEqual(preview?.url, "https://apple.com")
    XCTAssertEqual(preview?.title, "Apple")
  }

  func testExtractLinkPreview_withCorruptData_returnsNil() {
    let corruptData = Data([0x00, 0x01, 0x02, 0x03])
    let preview = LinkPreviewExtractor.extract(from: corruptData)
    XCTAssertNil(preview)
  }

  func testExtractLinkPreview_withEmptyData_returnsNil() {
    let preview = LinkPreviewExtractor.extract(from: Data())
    XCTAssertNil(preview)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter LinkPreviewExtractionTests 2>&1 | tail -20`
Expected: FAIL — `LinkPreviewExtractor` doesn't exist

**Step 3: Create LinkPreviewExtractor**

Add extraction logic. The cleanest approach is a small utility since it's used from multiple query methods. Add to the bottom of `LinkPreview.swift` (or create a new file if preferred — keeping it in `LinkPreview.swift` is simpler):

In `MessageBridgeServer/Sources/MessageBridgeCore/Models/LinkPreview.swift`, append:

```swift
import LinkPresentation

/// Extracts LinkPreview from iMessage's NSKeyedArchived payload_data blobs
public enum LinkPreviewExtractor {
  /// Extract link preview from an NSKeyedArchiver-encoded LPLinkMetadata blob
  public static func extract(from data: Data) -> LinkPreview? {
    guard !data.isEmpty else { return nil }

    let metadata: LPLinkMetadata?
    do {
      let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
      unarchiver.requiresSecureCoding = false
      metadata = unarchiver.decodeObject(
        of: LPLinkMetadata.self, forKey: NSKeyedArchiveRootObjectKey
      )
      unarchiver.finishDecoding()
    } catch {
      return nil
    }

    guard let metadata = metadata, let url = metadata.url else {
      return nil
    }

    return LinkPreview(
      url: url.absoluteString,
      title: metadata.title,
      summary: nil,  // LPLinkMetadata doesn't expose summary directly
      siteName: nil,  // Not available from the archived object
      imageBase64: nil  // Image handled separately from pluginPayloadAttachment
    )
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeServer && swift test --filter LinkPreviewExtractionTests 2>&1 | tail -20`
Expected: All 3 tests PASS

**Step 5: Wire extraction into fetchMessagesFromDB**

In `ChatDatabase.swift`, modify `fetchMessagesFromDB`:

1. Add `balloon_bundle_id` and `payload_data` to the SQL SELECT:
```sql
SELECT
    m.ROWID as id,
    m.guid,
    m.text,
    m.attributedBody,
    m.date,
    m.is_from_me,
    m.handle_id,
    m.balloon_bundle_id,
    m.payload_data
FROM message m
...
```

2. After building the `Message`, extract link preview:
```swift
// Extract link preview from payload_data if this is a URL balloon
var linkPreview: LinkPreview? = nil
let balloonBundleId: String? = row["balloon_bundle_id"]
if balloonBundleId == "com.apple.messages.URLBalloonProvider",
   let payloadData: Data = row["payload_data"] {
  linkPreview = LinkPreviewExtractor.extract(from: payloadData)
}

// If we have a link preview, find preview image from attachments before filtering
if linkPreview != nil {
  let previewAttachment = allAttachments.first {
    $0.filename.contains("pluginPayloadAttachment") && $0.isImage
  }
  if let previewAttachment = previewAttachment,
     let filePath = /* need file_path from the query */ ... {
    linkPreview = LinkPreview(
      url: linkPreview!.url,
      title: linkPreview!.title,
      summary: linkPreview!.summary,
      siteName: linkPreview!.siteName,
      imageBase64: generateThumbnail(forFilePath: filePath)
    )
  }
}

return Message(
  id: messageId,
  guid: row["guid"],
  text: messageText,
  date: Message.dateFromAppleTimestamp(row["date"]),
  isFromMe: (row["is_from_me"] as Int?) == 1,
  handleId: row["handle_id"],
  conversationId: conversationId,
  attachments: allAttachments.filter { !$0.shouldFilter },
  linkPreview: linkPreview
)
```

**Important implementation note:** The current `fetchAttachmentsForMessage` doesn't return the file_path. You need to either:
- (a) Modify `fetchAttachmentsForMessage` to also return file paths for preview images, or
- (b) Fetch the preview image file path with a separate query for link preview messages, or
- (c) Add a `filePath` property to the Attachment struct for internal use

Option (a) is simplest: have `fetchAttachmentsForMessage` return `[(Attachment, String?)]` tuples (attachment + optional file path), then use the file path for preview image thumbnail generation before filtering. However, this changes the internal API.

The most minimal approach: in `fetchAttachmentsForMessage`, before filtering, grab the preview image thumbnail. Restructure as:

```swift
// In fetchMessagesFromDB, change the flow:
let allAttachments = try self.fetchAttachmentsForMessage(db: db, messageId: messageId)

// Extract link preview
var linkPreview: LinkPreview? = nil
let balloonBundleId: String? = row["balloon_bundle_id"]
if balloonBundleId == "com.apple.messages.URLBalloonProvider",
   let payloadData: Data = row["payload_data"] {
  linkPreview = LinkPreviewExtractor.extract(from: payloadData)
}

// Get preview image from plugin attachments (before they get filtered)
if linkPreview != nil {
  let previewImageBase64 = self.fetchLinkPreviewImage(db: db, messageId: messageId)
  if let imageBase64 = previewImageBase64 {
    linkPreview = LinkPreview(
      url: linkPreview!.url,
      title: linkPreview!.title,
      summary: linkPreview!.summary,
      siteName: linkPreview!.siteName,
      imageBase64: imageBase64
    )
  }
}

// Filter junk attachments
let filteredAttachments = allAttachments.filter { !$0.shouldFilter }
```

Add a new private helper `fetchLinkPreviewImage`:

```swift
/// Fetch the preview image for a link preview message.
/// Looks for pluginPayloadAttachment image files and generates a thumbnail.
private nonisolated func fetchLinkPreviewImage(db: Database, messageId: Int64) -> String? {
  let sql = """
    SELECT a.filename as file_path, a.mime_type
    FROM attachment a
    JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
    WHERE maj.message_id = ?
      AND a.transfer_name LIKE '%pluginPayloadAttachment%'
      AND a.mime_type LIKE 'image/%'
    LIMIT 1
    """

  guard let row = try? Row.fetchOne(db, sql: sql, arguments: [messageId]),
        let filePath: String = row["file_path"]
  else {
    return nil
  }

  return generateThumbnail(forFilePath: filePath)
}
```

**Step 6: Run full server test suite**

Run: `cd MessageBridgeServer && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 7: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Models/LinkPreview.swift \
       MessageBridgeServer/Sources/MessageBridgeCore/Database/ChatDatabase.swift \
       MessageBridgeServer/Tests/MessageBridgeCoreTests/LinkPreviewExtractionTests.swift
git commit -m "feat(server): extract LPLinkMetadata from payload_data for link previews"
```

---

### Task 4: Client — Add LinkPreview to Client Models

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/Models.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/LinkPreviewModelTests.swift` (create)

**Step 1: Write the failing test**

Create `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/LinkPreviewModelTests.swift`:

```swift
import XCTest

@testable import MessageBridgeClientCore

final class LinkPreviewModelTests: XCTestCase {

  func testLinkPreview_decodesFromJSON() throws {
    let json = """
      {
        "url": "https://apple.com",
        "title": "Apple",
        "summary": "Innovation at its finest.",
        "siteName": "Apple",
        "imageBase64": "base64data"
      }
      """
    let decoded = try JSONDecoder().decode(LinkPreview.self, from: json.data(using: .utf8)!)

    XCTAssertEqual(decoded.url, "https://apple.com")
    XCTAssertEqual(decoded.title, "Apple")
    XCTAssertEqual(decoded.summary, "Innovation at its finest.")
    XCTAssertEqual(decoded.siteName, "Apple")
    XCTAssertEqual(decoded.imageBase64, "base64data")
  }

  func testLinkPreview_decodesWithNilOptionals() throws {
    let json = """
      {"url": "https://example.com"}
      """
    let decoded = try JSONDecoder().decode(LinkPreview.self, from: json.data(using: .utf8)!)

    XCTAssertEqual(decoded.url, "https://example.com")
    XCTAssertNil(decoded.title)
    XCTAssertNil(decoded.summary)
  }

  func testMessage_decodesLinkPreview() throws {
    let json = """
      {
        "id": 1,
        "guid": "g1",
        "text": "https://apple.com",
        "date": 0,
        "isFromMe": true,
        "conversationId": "c1",
        "linkPreview": {
          "url": "https://apple.com",
          "title": "Apple"
        }
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)

    XCTAssertNotNil(message.linkPreview)
    XCTAssertEqual(message.linkPreview?.url, "https://apple.com")
    XCTAssertEqual(message.linkPreview?.title, "Apple")
  }

  func testMessage_decodesWithoutLinkPreview() throws {
    let json = """
      {
        "id": 1,
        "guid": "g1",
        "text": "Hello",
        "date": 0,
        "isFromMe": true,
        "conversationId": "c1"
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)

    XCTAssertNil(message.linkPreview)
  }

  func testLinkPreview_domain_extractsHost() {
    let preview = LinkPreview(url: "https://www.apple.com/iphone/compare/", title: nil)
    XCTAssertEqual(preview.domain, "apple.com")
  }

  func testLinkPreview_domain_handlesNoDomain() {
    let preview = LinkPreview(url: "not-a-url", title: nil)
    XCTAssertEqual(preview.domain, "not-a-url")
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeClient && swift test --filter LinkPreviewModelTests 2>&1 | tail -20`
Expected: FAIL — `LinkPreview` type doesn't exist

**Step 3: Add LinkPreview and update Message**

In `MessageBridgeClient/Sources/MessageBridgeClientCore/Models/Models.swift`, add before the `DeliveryStatus` enum:

```swift
// MARK: - LinkPreview

/// Rich link preview metadata from server (extracted from iMessage payload_data)
public struct LinkPreview: Codable, Hashable, Sendable {
  public let url: String
  public let title: String?
  public let summary: String?
  public let siteName: String?
  public let imageBase64: String?

  public init(
    url: String,
    title: String? = nil,
    summary: String? = nil,
    siteName: String? = nil,
    imageBase64: String? = nil
  ) {
    self.url = url
    self.title = title
    self.summary = summary
    self.siteName = siteName
    self.imageBase64 = imageBase64
  }

  /// Extract domain from URL for display (e.g., "apple.com" from "https://www.apple.com/...")
  public var domain: String {
    guard let urlObj = URL(string: url), let host = urlObj.host() else {
      return url
    }
    // Strip "www." prefix
    if host.hasPrefix("www.") {
      return String(host.dropFirst(4))
    }
    return host
  }

  /// Decoded image data from base64
  public var imageData: Data? {
    guard let imageBase64 = imageBase64 else { return nil }
    return Data(base64Encoded: imageBase64)
  }
}
```

Add `linkPreview` to the `Message` struct:

1. Add property: `public let linkPreview: LinkPreview?`
2. Add to `CodingKeys`: `case linkPreview`
3. Add to `init(...)`: parameter `linkPreview: LinkPreview? = nil` and assign
4. Add to `init(from decoder:)`: `linkPreview = try container.decodeIfPresent(LinkPreview.self, forKey: .linkPreview)`

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter LinkPreviewModelTests 2>&1 | tail -20`
Expected: All 6 tests PASS

**Step 5: Run full client test suite**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests pass (check for compilation errors in existing tests that construct Message — they should be fine since `linkPreview` defaults to nil)

**Step 6: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Models/Models.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/LinkPreviewModelTests.swift
git commit -m "feat(client): add LinkPreview model to Message"
```

---

### Task 5: Client — Update LinkPreviewRenderer for Rich Cards

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/LinkPreviewRenderer.swift`
- Modify: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/LinkPreviewRendererTests.swift`

**Step 1: Write the failing tests**

Replace `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/LinkPreviewRendererTests.swift`:

```swift
import XCTest

@testable import MessageBridgeClientCore

final class LinkPreviewRendererTests: XCTestCase {
  let renderer = LinkPreviewRenderer()

  func testId_isLinkPreview() {
    XCTAssertEqual(renderer.id, "link-preview")
  }

  func testPriority_is100() {
    XCTAssertEqual(renderer.priority, 100)
  }

  func testCanRender_withLinkPreview_returnsTrue() {
    let preview = LinkPreview(url: "https://apple.com", title: "Apple")
    let message = makeMessage("https://apple.com", linkPreview: preview)
    XCTAssertTrue(renderer.canRender(message))
  }

  func testCanRender_withoutLinkPreview_returnsFalse() {
    let message = makeMessage("Check https://apple.com", linkPreview: nil)
    XCTAssertFalse(renderer.canRender(message))
  }

  func testCanRender_nilText_withLinkPreview_returnsTrue() {
    let preview = LinkPreview(url: "https://apple.com", title: "Apple")
    let message = makeMessage(nil, linkPreview: preview)
    XCTAssertTrue(renderer.canRender(message))
  }

  func testCanRender_noLinkPreview_noURL_returnsFalse() {
    let message = makeMessage("No links here", linkPreview: nil)
    XCTAssertFalse(renderer.canRender(message))
  }

  private func makeMessage(_ text: String?, linkPreview: LinkPreview? = nil) -> Message {
    Message(
      id: 1, guid: "g1", text: text, date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1", linkPreview: linkPreview)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeClient && swift test --filter LinkPreviewRendererTests 2>&1 | tail -20`
Expected: FAIL — `canRender` still uses URL detection, not `linkPreview`

**Step 3: Update LinkPreviewRenderer**

Replace `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/LinkPreviewRenderer.swift`:

```swift
import SwiftUI

/// Renderer for messages with rich link previews.
///
/// Displays an iMessage-style card with image, title, and domain.
/// Uses server-provided metadata extracted from iMessage's payload_data.
public struct LinkPreviewRenderer: MessageRenderer {
  public let id = "link-preview"
  public let priority = 100

  public init() {}

  public func canRender(_ message: Message) -> Bool {
    message.linkPreview != nil
  }

  @MainActor
  public func render(_ message: Message) -> AnyView {
    guard let preview = message.linkPreview else {
      return AnyView(EmptyView())
    }

    return AnyView(
      VStack(alignment: .leading, spacing: 4) {
        // Message text (if any, and different from the URL)
        if let text = message.text, !text.isEmpty {
          Text(text)
            .textSelection(.enabled)
        }

        // Link preview card
        LinkPreviewCard(preview: preview)
      }
    )
  }
}

struct LinkPreviewCard: View {
  let preview: LinkPreview

  var body: some View {
    Link(destination: URL(string: preview.url) ?? URL(string: "about:blank")!) {
      VStack(alignment: .leading, spacing: 0) {
        // Preview image
        if let imageData = preview.imageData,
           let nsImage = NSImage(data: imageData) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: 280, maxHeight: 200)
            .clipped()
        }

        // Title + domain
        VStack(alignment: .leading, spacing: 4) {
          if let title = preview.title, !title.isEmpty {
            Text(title)
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.primary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }

          if let summary = preview.summary, !summary.isEmpty {
            Text(summary)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }

          HStack(spacing: 4) {
            Image(systemName: "link")
              .font(.caption2)
            Text(preview.domain)
              .font(.caption)
          }
          .foregroundStyle(.secondary)
        }
        .padding(10)
      }
      .frame(maxWidth: 280)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
      )
    }
    .buttonStyle(.plain)
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter LinkPreviewRendererTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Run full client test suite**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 6: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Messages/LinkPreviewRenderer.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/LinkPreviewRendererTests.swift
git commit -m "feat(client): iMessage-style link preview cards from server metadata"
```

---

### Task 6: Client — Remove LinkPreviewCache

**Files:**
- Delete: `MessageBridgeClient/Sources/MessageBridgeClientCore/Services/LinkPreviewCache.swift`
- Delete: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/LinkPreviewCacheTests.swift`

**Step 1: Check for usages of LinkPreviewCache**

Search the codebase for any imports or references to `LinkPreviewCache`. If it's only used in the cache test file and nowhere else in production code, it's safe to delete.

Run: `grep -r "LinkPreviewCache" MessageBridgeClient/Sources/`

If no results (or only the file itself), proceed with deletion.

**Step 2: Delete files**

```bash
rm MessageBridgeClient/Sources/MessageBridgeClientCore/Services/LinkPreviewCache.swift
rm MessageBridgeClient/Tests/MessageBridgeClientCoreTests/LinkPreviewCacheTests.swift
```

**Step 3: Run full client test suite**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -20`
Expected: All tests pass (no compilation errors from missing type)

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor(client): remove unused LinkPreviewCache"
```

---

### Task 7: Full Verification & CLAUDE.md Update

**Files:**
- Modify: `CLAUDE.md` (Current Focus section)

**Step 1: Run both test suites**

Run: `cd MessageBridgeServer && swift test && cd ../MessageBridgeClient && swift test`
Expected: All tests pass in both projects

**Step 2: Update CLAUDE.md Current Focus**

Update the "Current Focus" section:

```markdown
**Active Work:** None - ready for new work

**Last Session:** Link Preview & Attachment Filtering
- Filtered junk attachments (pluginPayloadAttachment, stickers, zero-byte) server-side
- Added LinkPreview model to server and client Message
- Server extracts LPLinkMetadata from message.payload_data via NSKeyedUnarchiver
- Server generates preview image thumbnails from pluginPayloadAttachment files
- Client renders iMessage-style link preview cards (image + title + domain)
- Removed unused LinkPreviewCache (no more client-side URL fetching)
- All server + client tests pass
```

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for link preview session"
```
