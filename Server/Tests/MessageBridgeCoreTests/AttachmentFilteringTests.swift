import XCTest

@testable import MessageBridgeCore

final class AttachmentFilteringTests: XCTestCase {

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
