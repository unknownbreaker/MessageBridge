import XCTest

@testable import MessageBridgeCore

final class AttachmentTests: XCTestCase {

  // MARK: - Attachment Type Detection Tests

  func testAttachmentType_withImageMimeType_returnsImage() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "photo.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 1024,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .image)
    XCTAssertTrue(attachment.isImage)
    XCTAssertFalse(attachment.isVideo)
    XCTAssertFalse(attachment.isAudio)
    XCTAssertFalse(attachment.isDocument)
  }

  func testAttachmentType_withPngMimeType_returnsImage() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "screenshot.png",
      mimeType: "image/png",
      uti: nil,
      size: 2048,
      isOutgoing: true,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .image)
    XCTAssertTrue(attachment.isImage)
  }

  func testAttachmentType_withHeicMimeType_returnsImage() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "photo.heic",
      mimeType: "image/heic",
      uti: nil,
      size: 3072,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .image)
    XCTAssertTrue(attachment.isImage)
  }

  func testAttachmentType_withVideoMimeType_returnsVideo() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "video.mp4",
      mimeType: "video/mp4",
      uti: nil,
      size: 10_000_000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .video)
    XCTAssertTrue(attachment.isVideo)
    XCTAssertFalse(attachment.isImage)
  }

  func testAttachmentType_withQuicktimeMimeType_returnsVideo() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "video.mov",
      mimeType: "video/quicktime",
      uti: nil,
      size: 50_000_000,
      isOutgoing: true,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .video)
    XCTAssertTrue(attachment.isVideo)
  }

  func testAttachmentType_withAudioMimeType_returnsAudio() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "voice.m4a",
      mimeType: "audio/m4a",
      uti: nil,
      size: 500_000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .audio)
    XCTAssertTrue(attachment.isAudio)
    XCTAssertFalse(attachment.isImage)
    XCTAssertFalse(attachment.isVideo)
  }

  func testAttachmentType_withMp3MimeType_returnsAudio() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "song.mp3",
      mimeType: "audio/mpeg",
      uti: nil,
      size: 3_000_000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .audio)
    XCTAssertTrue(attachment.isAudio)
  }

  func testAttachmentType_withPdfMimeType_returnsDocument() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "document.pdf",
      mimeType: "application/pdf",
      uti: nil,
      size: 100_000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .document)
    XCTAssertTrue(attachment.isDocument)
    XCTAssertFalse(attachment.isImage)
  }

  func testAttachmentType_withUnknownMimeType_returnsDocument() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "file.xyz",
      mimeType: "application/octet-stream",
      uti: nil,
      size: 1000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .document)
    XCTAssertTrue(attachment.isDocument)
  }

  func testAttachmentType_withNilMimeType_andImageUTI_returnsImage() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "photo.jpg",
      mimeType: nil,
      uti: "public.jpeg-image",
      size: 1024,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .image)
    XCTAssertTrue(attachment.isImage)
  }

  func testAttachmentType_withNilMimeType_andVideoUTI_returnsVideo() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "video.mov",
      mimeType: nil,
      uti: "com.apple.quicktime-movie",
      size: 10_000_000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .video)
    XCTAssertTrue(attachment.isVideo)
  }

  func testAttachmentType_withNilMimeType_andAudioUTI_returnsAudio() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "voice.caf",
      mimeType: nil,
      uti: "com.apple.coreaudio-format",
      size: 500_000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .audio)
    XCTAssertTrue(attachment.isAudio)
  }

  func testAttachmentType_withNilMimeTypeAndUTI_returnsDocument() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "file.dat",
      mimeType: nil,
      uti: nil,
      size: 1000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.attachmentType, .document)
    XCTAssertTrue(attachment.isDocument)
  }

  // MARK: - Formatted Size Tests

  func testFormattedSize_withBytes_formatsCorrectly() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "tiny.txt",
      mimeType: "text/plain",
      uti: nil,
      size: 500,
      isOutgoing: false,
      isSticker: false
    )

    // ByteCountFormatter returns "500 bytes" or similar
    XCTAssertTrue(
      attachment.formattedSize.contains("500")
        || attachment.formattedSize.lowercased().contains("byte"))
  }

  func testFormattedSize_withKilobytes_formatsCorrectly() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "small.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 150_000,  // ~150 KB
      isOutgoing: false,
      isSticker: false
    )

    // Should contain "KB" for kilobytes
    XCTAssertTrue(
      attachment.formattedSize.contains("KB"), "Expected KB in '\(attachment.formattedSize)'")
  }

  func testFormattedSize_withMegabytes_formatsCorrectly() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "photo.heic",
      mimeType: "image/heic",
      uti: nil,
      size: 5_000_000,  // ~5 MB
      isOutgoing: false,
      isSticker: false
    )

    // Should contain "MB" for megabytes
    XCTAssertTrue(
      attachment.formattedSize.contains("MB"), "Expected MB in '\(attachment.formattedSize)'")
  }

  func testFormattedSize_withGigabytes_formatsCorrectly() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "video.mov",
      mimeType: "video/quicktime",
      uti: nil,
      size: 2_500_000_000,  // ~2.5 GB
      isOutgoing: false,
      isSticker: false
    )

    // Should contain "GB" for gigabytes
    XCTAssertTrue(
      attachment.formattedSize.contains("GB"), "Expected GB in '\(attachment.formattedSize)'")
  }

  func testFormattedSize_withZero_formatsCorrectly() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "empty.txt",
      mimeType: "text/plain",
      uti: nil,
      size: 0,
      isOutgoing: false,
      isSticker: false
    )

    // Should handle zero gracefully
    XCTAssertFalse(attachment.formattedSize.isEmpty)
  }

  // MARK: - Sticker and Outgoing Tests

  func testAttachment_isSticker_returnsCorrectValue() {
    let sticker = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "sticker.png",
      mimeType: "image/png",
      uti: nil,
      size: 50_000,
      isOutgoing: false,
      isSticker: true
    )

    XCTAssertTrue(sticker.isSticker)
  }

  func testAttachment_isOutgoing_returnsCorrectValue() {
    let outgoing = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "sent.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 100_000,
      isOutgoing: true,
      isSticker: false
    )

    XCTAssertTrue(outgoing.isOutgoing)
  }

  // MARK: - Message with Attachments Tests

  func testMessage_hasAttachments_withAttachments_returnsTrue() {
    let attachment = Attachment(
      id: 1,
      guid: "att-guid",
      filename: "photo.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 1024,
      isOutgoing: false,
      isSticker: false
    )

    let message = Message(
      id: 1,
      guid: "msg-guid",
      text: "Check out this photo",
      date: Date(),
      isFromMe: true,
      handleId: nil,
      conversationId: "chat-1",
      attachments: [attachment]
    )

    XCTAssertTrue(message.hasAttachments)
    XCTAssertEqual(message.attachments.count, 1)
  }

  func testMessage_hasAttachments_withoutAttachments_returnsFalse() {
    let message = Message(
      id: 1,
      guid: "msg-guid",
      text: "Just text, no attachments",
      date: Date(),
      isFromMe: true,
      handleId: nil,
      conversationId: "chat-1",
      attachments: []
    )

    XCTAssertFalse(message.hasAttachments)
    XCTAssertTrue(message.attachments.isEmpty)
  }

  func testMessage_defaultAttachments_isEmpty() {
    let message = Message(
      id: 1,
      guid: "msg-guid",
      text: "Default message",
      date: Date(),
      isFromMe: true,
      handleId: nil,
      conversationId: "chat-1"
    )

    XCTAssertFalse(message.hasAttachments)
    XCTAssertTrue(message.attachments.isEmpty)
  }

  func testMessage_withMultipleAttachments_returnsAll() {
    let attachments = [
      Attachment(
        id: 1, guid: "att-1", filename: "photo1.jpg", mimeType: "image/jpeg", uti: nil, size: 1000,
        isOutgoing: false, isSticker: false),
      Attachment(
        id: 2, guid: "att-2", filename: "photo2.jpg", mimeType: "image/jpeg", uti: nil, size: 2000,
        isOutgoing: false, isSticker: false),
      Attachment(
        id: 3, guid: "att-3", filename: "video.mp4", mimeType: "video/mp4", uti: nil,
        size: 5_000_000, isOutgoing: false, isSticker: false),
    ]

    let message = Message(
      id: 1,
      guid: "msg-guid",
      text: "Multiple attachments",
      date: Date(),
      isFromMe: true,
      handleId: nil,
      conversationId: "chat-1",
      attachments: attachments
    )

    XCTAssertTrue(message.hasAttachments)
    XCTAssertEqual(message.attachments.count, 3)
    XCTAssertEqual(message.attachments[0].filename, "photo1.jpg")
    XCTAssertEqual(message.attachments[2].mimeType, "video/mp4")
  }

  // MARK: - Attachment Codable Tests

  func testAttachment_encodesAndDecodes() throws {
    let original = Attachment(
      id: 123,
      guid: "test-guid-123",
      filename: "test-photo.jpg",
      mimeType: "image/jpeg",
      uti: "public.jpeg",
      size: 456789,
      isOutgoing: true,
      isSticker: false,
      thumbnailBase64: "base64encodeddata"
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Attachment.self, from: data)

    XCTAssertEqual(decoded.id, original.id)
    XCTAssertEqual(decoded.guid, original.guid)
    XCTAssertEqual(decoded.filename, original.filename)
    XCTAssertEqual(decoded.mimeType, original.mimeType)
    XCTAssertEqual(decoded.uti, original.uti)
    XCTAssertEqual(decoded.size, original.size)
    XCTAssertEqual(decoded.isOutgoing, original.isOutgoing)
    XCTAssertEqual(decoded.isSticker, original.isSticker)
    XCTAssertEqual(decoded.thumbnailBase64, original.thumbnailBase64)
  }

  func testAttachment_decodesWithNilOptionals() throws {
    let json = """
      {
          "id": 1,
          "guid": "test-guid",
          "filename": "file.dat",
          "size": 100,
          "isOutgoing": false,
          "isSticker": false
      }
      """

    let decoder = JSONDecoder()
    let attachment = try decoder.decode(Attachment.self, from: json.data(using: .utf8)!)

    XCTAssertEqual(attachment.id, 1)
    XCTAssertNil(attachment.mimeType)
    XCTAssertNil(attachment.uti)
    XCTAssertNil(attachment.thumbnailBase64)
  }

  // MARK: - Metadata Tests

  func testMetadata_defaultsToNil() {
    let attachment = Attachment(
      id: 1,
      guid: "test",
      filename: "test.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 1000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertNil(attachment.metadata)
  }

  func testMetadata_canBeSet() {
    let metadata = AttachmentMetadata(width: 1920, height: 1080)
    let attachment = Attachment(
      id: 1,
      guid: "test",
      filename: "test.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 1000,
      isOutgoing: false,
      isSticker: false,
      metadata: metadata
    )

    XCTAssertEqual(attachment.metadata?.width, 1920)
    XCTAssertEqual(attachment.metadata?.height, 1080)
  }

  // MARK: - ThumbnailURL Tests

  func testThumbnailURL_forImage_returnsPath() {
    let attachment = Attachment(
      id: 123,
      guid: "test",
      filename: "photo.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 1000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.thumbnailURL, "/attachments/123/thumbnail")
  }

  func testThumbnailURL_forVideo_returnsPath() {
    let attachment = Attachment(
      id: 456,
      guid: "test",
      filename: "video.mp4",
      mimeType: "video/mp4",
      uti: nil,
      size: 5000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertEqual(attachment.thumbnailURL, "/attachments/456/thumbnail")
  }

  func testThumbnailURL_forAudio_returnsNil() {
    let attachment = Attachment(
      id: 789,
      guid: "test",
      filename: "audio.mp3",
      mimeType: "audio/mpeg",
      uti: nil,
      size: 2000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertNil(attachment.thumbnailURL)
  }

  func testThumbnailURL_forDocument_returnsNil() {
    let attachment = Attachment(
      id: 101,
      guid: "test",
      filename: "doc.pdf",
      mimeType: "application/pdf",
      uti: nil,
      size: 3000,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertNil(attachment.thumbnailURL)
  }

  func testThumbnailURL_withNoMimeType_returnsNil() {
    let attachment = Attachment(
      id: 102,
      guid: "test",
      filename: "unknown",
      mimeType: nil,
      uti: nil,
      size: 100,
      isOutgoing: false,
      isSticker: false
    )

    XCTAssertNil(attachment.thumbnailURL)
  }
}
