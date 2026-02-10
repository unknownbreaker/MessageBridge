import XCTest

@testable import MessageBridgeClientCore

/// Blind audit tests for M3.1 (Attachments Display).
/// Written from spec.md acceptance criteria without reading implementation.
final class M3_1_AttachmentsDisplayAuditTests: XCTestCase {

  // MARK: - AC1: Images show as thumbnails in message bubble

  /// Spec: "Images show as thumbnails in message bubble"
  func testSingleImageRenderer_canRender_imageAttachment() {
    let renderer = SingleImageRenderer()
    let attachment = makeAttachment(mimeType: "image/jpeg", filename: "photo.jpg")
    XCTAssertTrue(renderer.canRender([attachment]))
  }

  /// Spec: "Images show as thumbnails in message bubble" (multiple images)
  func testImageGalleryRenderer_canRender_multipleImages() {
    let renderer = ImageGalleryRenderer()
    let a1 = makeAttachment(id: 1, mimeType: "image/jpeg", filename: "a.jpg")
    let a2 = makeAttachment(id: 2, mimeType: "image/png", filename: "b.png")
    XCTAssertTrue(renderer.canRender([a1, a2]))
  }

  /// Spec: Thumbnails embedded in attachment data
  func testAttachment_thumbnailData_decodesBase64() {
    let base64 = Data("fakejpeg".utf8).base64EncodedString()
    let attachment = Attachment(
      id: 1, guid: "g", filename: "photo.jpg", mimeType: "image/jpeg",
      uti: nil, size: 1000, isOutgoing: false, isSticker: false,
      thumbnailBase64: base64)
    XCTAssertNotNil(attachment.thumbnailData)
  }

  /// Spec: Registry selects image renderer over document fallback
  func testRegistry_selectsImageRenderer_overDocumentFallback() {
    let registry = AttachmentRendererRegistry.shared
    registry.reset()
    registry.register(DocumentRenderer())
    registry.register(SingleImageRenderer())
    let attachment = makeAttachment(mimeType: "image/jpeg", filename: "photo.jpg")
    let selected = registry.renderer(for: [attachment])
    XCTAssertEqual(selected.id, "single-image")
    registry.reset()
  }

  // MARK: - AC2: Tap thumbnail to open fullscreen

  /// Spec: "Tap thumbnail to open fullscreen"
  /// Structural test — verify SingleImageRenderer exists with appropriate priority
  func testSingleImageRenderer_hasPriority_greaterThanFallback() {
    let renderer = SingleImageRenderer()
    let fallback = DocumentRenderer()
    XCTAssertGreaterThan(renderer.priority, fallback.priority)
  }

  /// Spec: Message model carries attachments for rendering
  func testMessage_hasAttachments_whenImageAttached() {
    let attachment = makeAttachment(mimeType: "image/jpeg", filename: "photo.jpg")
    let msg = makeMessage(attachments: [attachment])
    XCTAssertTrue(msg.hasAttachments)
    XCTAssertEqual(msg.attachments.count, 1)
  }

  // MARK: - AC3: Videos show thumbnail with play button

  /// Spec: "Videos show thumbnail with play button"
  func testVideoRenderer_canRender_videoAttachment() {
    let renderer = VideoRenderer()
    let attachment = makeAttachment(mimeType: "video/mp4", filename: "clip.mp4")
    XCTAssertTrue(renderer.canRender([attachment]))
  }

  /// Spec: Video renderer rejects non-video
  func testVideoRenderer_cannotRender_imageAttachment() {
    let renderer = VideoRenderer()
    let attachment = makeAttachment(mimeType: "image/jpeg", filename: "photo.jpg")
    XCTAssertFalse(renderer.canRender([attachment]))
  }

  /// Spec: Registry selects video renderer for video attachments
  func testRegistry_selectsVideoRenderer_forVideo() {
    let registry = AttachmentRendererRegistry.shared
    registry.reset()
    registry.register(DocumentRenderer())
    registry.register(VideoRenderer())
    let attachment = makeAttachment(mimeType: "video/mp4", filename: "clip.mp4")
    let selected = registry.renderer(for: [attachment])
    XCTAssertEqual(selected.id, "video")
    registry.reset()
  }

  // MARK: - AC4: Files show icon, name, and size

  /// Spec: "Files show icon, name, and size"
  func testDocumentRenderer_canRender_anyAttachment() {
    let renderer = DocumentRenderer()
    let attachment = makeAttachment(mimeType: "application/pdf", filename: "doc.pdf")
    XCTAssertTrue(renderer.canRender([attachment]))
  }

  /// Spec: File attachment has accessible filename
  func testAttachment_filename_isAccessible() {
    let attachment = makeAttachment(mimeType: "application/pdf", filename: "report.pdf")
    XCTAssertEqual(attachment.filename, "report.pdf")
  }

  /// Spec: File attachment has formatted size
  func testAttachment_formattedSize_isNotEmpty() {
    let attachment = Attachment(
      id: 1, guid: "g", filename: "report.pdf", mimeType: "application/pdf",
      uti: nil, size: 150_000, isOutgoing: false, isSticker: false)
    XCTAssertFalse(attachment.formattedSize.isEmpty)
    XCTAssertTrue(attachment.formattedSize.contains("KB"))
  }

  /// Spec: Document renderer is the lowest-priority fallback
  func testDocumentRenderer_isLowestPriority() {
    XCTAssertEqual(DocumentRenderer().priority, 0)
  }

  // MARK: - AC5: Attachments download on demand

  /// Spec: "Attachments download on demand"
  /// Structural test — verify BridgeServiceProtocol exposes fetchAttachment
  func testBridgeServiceProtocol_hasFetchAttachmentMethod() {
    // Verify the method signature exists on the protocol
    let _: (any BridgeServiceProtocol) -> (Int64) async throws -> Data =
      { conn in conn.fetchAttachment }
  }

  /// Spec: Thumbnail data is available without extra download
  func testAttachment_thumbnailData_availableWithoutDownload() {
    let base64 = Data("thumb".utf8).base64EncodedString()
    let attachment = Attachment(
      id: 1, guid: "g", filename: "photo.jpg", mimeType: "image/jpeg",
      uti: nil, size: 5000, isOutgoing: false, isSticker: false,
      thumbnailBase64: base64)
    // Thumbnail is embedded — no network call needed
    XCTAssertNotNil(attachment.thumbnailData)
    XCTAssertEqual(attachment.thumbnailData, Data(base64Encoded: base64))
  }

  /// Spec: Nil thumbnail means download is needed
  func testAttachment_nilThumbnail_requiresDownload() {
    let attachment = makeAttachment(mimeType: "image/jpeg", filename: "photo.jpg")
    XCTAssertNil(attachment.thumbnailData)
  }

  // MARK: - Edge Cases

  /// Audio renderer exists and can render audio
  func testAudioRenderer_canRender_audioAttachment() {
    let renderer = AudioRenderer()
    let attachment = makeAttachment(mimeType: "audio/m4a", filename: "voice.m4a")
    XCTAssertTrue(renderer.canRender([attachment]))
  }

  /// Registry falls back to document for unknown types
  func testRegistry_fallsBackToDocument_forUnknownType() {
    let registry = AttachmentRendererRegistry.shared
    registry.reset()
    registry.register(DocumentRenderer())
    registry.register(SingleImageRenderer())
    registry.register(VideoRenderer())
    let attachment = makeAttachment(mimeType: "application/octet-stream", filename: "data.bin")
    let selected = registry.renderer(for: [attachment])
    XCTAssertEqual(selected.id, "document")
    registry.reset()
  }

  // MARK: - Helpers

  private func makeAttachment(
    id: Int64 = 1, mimeType: String, filename: String
  ) -> Attachment {
    Attachment(
      id: id, guid: "g\(id)", filename: filename, mimeType: mimeType,
      uti: nil, size: 1000, isOutgoing: false, isSticker: false)
  }

  private func makeMessage(attachments: [Attachment] = []) -> Message {
    Message(
      id: 1, guid: "m1", text: "Check this out", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1",
      attachments: attachments)
  }
}

// MARK: - Audit Findings (2026-01-27)
//
// Build attempt 1: FAILED — BridgeConnection.shared does not exist (it's an actor, not singleton).
//   Fix: Changed to BridgeServiceProtocol method reference.
//
// Build attempt 2: FAILED — 'any' has no effect on concrete type 'BridgeConnection'.
//   Fix: BridgeConnection is an actor conforming to BridgeServiceProtocol. Used protocol name.
//
// Build attempt 3: PASSED — all 18 tests compiled and passed.
//
// Findings:
//   ✅ AC1: SingleImageRenderer + ImageGalleryRenderer handle image attachments correctly
//   ✅ AC2: SingleImageRenderer has higher priority than DocumentRenderer fallback
//   ✅ AC3: VideoRenderer handles video attachments, rejects non-video
//   ✅ AC4: DocumentRenderer is fallback (priority 0), filename + formattedSize accessible
//   ✅ AC5: BridgeServiceProtocol.fetchAttachment(id:) exists, thumbnailData decodes base64
//
// Remaining gaps (not testable at unit level):
//   ⚠️ Fullscreen image view needs carousel/swipe (M3.2 scope)
//   ⚠️ Video/audio playback not yet implemented (visual stubs only)
//   ⚠️ File download-to-disk not implemented (only in-memory fetch exists)
//
// All 18 tests: PASSED (0 failures)
