import XCTest

@testable import MessageBridgeClientCore

final class ImageGalleryRendererTests: XCTestCase {
  let renderer = ImageGalleryRenderer()

  func testId() { XCTAssertEqual(renderer.id, "image-gallery") }
  func testPriority() { XCTAssertEqual(renderer.priority, 100) }

  func testCanRender_twoImages_true() {
    XCTAssertTrue(renderer.canRender([makeImage(), makeImage()]))
  }

  func testCanRender_threeImages_true() {
    XCTAssertTrue(renderer.canRender([makeImage(), makeImage(), makeImage()]))
  }

  func testCanRender_singleImage_false() {
    XCTAssertFalse(renderer.canRender([makeImage()]))
  }

  func testCanRender_noImages_false() {
    XCTAssertFalse(renderer.canRender([makeAttachment(mime: "video/mp4")]))
  }

  func testCanRender_mixedWithTwoImages_true() {
    XCTAssertTrue(
      renderer.canRender([makeImage(), makeAttachment(mime: "video/mp4"), makeImage()]))
  }

  func testCanRender_empty_false() {
    XCTAssertFalse(renderer.canRender([]))
  }

  private func makeImage() -> Attachment {
    Attachment(
      id: Int64.random(in: 1...9999), guid: UUID().uuidString, filename: "img.jpg",
      mimeType: "image/jpeg", size: 1000, isOutgoing: false, isSticker: false)
  }

  private func makeAttachment(mime: String) -> Attachment {
    Attachment(
      id: Int64.random(in: 1...9999), guid: UUID().uuidString, filename: "file",
      mimeType: mime, size: 1000, isOutgoing: false, isSticker: false)
  }
}
