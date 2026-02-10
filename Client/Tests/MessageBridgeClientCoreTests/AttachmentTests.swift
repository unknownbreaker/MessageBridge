import XCTest

@testable import MessageBridgeClientCore

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
  }

  // MARK: - Formatted Size Tests

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

    XCTAssertTrue(attachment.formattedSize.contains("KB"))
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

    XCTAssertTrue(attachment.formattedSize.contains("MB"))
  }

  // MARK: - Thumbnail Data Tests

  func testThumbnailData_withValidBase64_returnsData() {
    let testString = "Hello, World!"
    let base64 = testString.data(using: .utf8)!.base64EncodedString()

    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "photo.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 1000,
      isOutgoing: false,
      isSticker: false,
      thumbnailBase64: base64
    )

    XCTAssertNotNil(attachment.thumbnailData)
    XCTAssertEqual(String(data: attachment.thumbnailData!, encoding: .utf8), testString)
  }

  func testThumbnailData_withNilBase64_returnsNil() {
    let attachment = Attachment(
      id: 1,
      guid: "test-guid",
      filename: "photo.jpg",
      mimeType: "image/jpeg",
      uti: nil,
      size: 1000,
      isOutgoing: false,
      isSticker: false,
      thumbnailBase64: nil
    )

    XCTAssertNil(attachment.thumbnailData)
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
      text: "Just text",
      date: Date(),
      isFromMe: true,
      handleId: nil,
      conversationId: "chat-1",
      attachments: []
    )

    XCTAssertFalse(message.hasAttachments)
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

  // MARK: - Codable Tests

  func testAttachment_decodesFromJSON() throws {
    let json = """
      {
          "id": 123,
          "guid": "test-guid-123",
          "filename": "photo.jpg",
          "mimeType": "image/jpeg",
          "uti": "public.jpeg",
          "size": 456789,
          "isOutgoing": true,
          "isSticker": false,
          "thumbnailBase64": "dGVzdA=="
      }
      """

    let decoder = JSONDecoder()
    let attachment = try decoder.decode(Attachment.self, from: json.data(using: .utf8)!)

    XCTAssertEqual(attachment.id, 123)
    XCTAssertEqual(attachment.guid, "test-guid-123")
    XCTAssertEqual(attachment.filename, "photo.jpg")
    XCTAssertEqual(attachment.mimeType, "image/jpeg")
    XCTAssertEqual(attachment.size, 456789)
    XCTAssertTrue(attachment.isOutgoing)
    XCTAssertFalse(attachment.isSticker)
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

    XCTAssertNil(attachment.mimeType)
    XCTAssertNil(attachment.uti)
    XCTAssertNil(attachment.thumbnailBase64)
  }

  func testMessage_decodesWithAttachments() throws {
    let json = """
      {
          "id": 1,
          "guid": "msg-guid",
          "text": "Check this out",
          "date": "2025-01-15T12:00:00Z",
          "isFromMe": true,
          "conversationId": "chat-1",
          "attachments": [
              {
                  "id": 100,
                  "guid": "att-guid",
                  "filename": "photo.jpg",
                  "mimeType": "image/jpeg",
                  "size": 1000,
                  "isOutgoing": true,
                  "isSticker": false
              }
          ]
      }
      """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)

    XCTAssertEqual(message.attachments.count, 1)
    XCTAssertEqual(message.attachments[0].filename, "photo.jpg")
    XCTAssertTrue(message.hasAttachments)
  }

  func testMessage_decodesWithEmptyAttachments() throws {
    let json = """
      {
          "id": 1,
          "guid": "msg-guid",
          "text": "Just text",
          "date": "2025-01-15T12:00:00Z",
          "isFromMe": true,
          "conversationId": "chat-1",
          "attachments": []
      }
      """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let message = try decoder.decode(Message.self, from: json.data(using: .utf8)!)

    XCTAssertTrue(message.attachments.isEmpty)
    XCTAssertFalse(message.hasAttachments)
  }
}
