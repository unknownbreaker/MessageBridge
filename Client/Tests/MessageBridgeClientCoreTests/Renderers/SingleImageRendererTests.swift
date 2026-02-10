import XCTest

@testable import MessageBridgeClientCore

final class SingleImageRendererTests: XCTestCase {
  let renderer = SingleImageRenderer()

  func testId() { XCTAssertEqual(renderer.id, "single-image") }
  func testPriority() { XCTAssertEqual(renderer.priority, 50) }

  func testCanRender_singleImage_true() {
    let a = Attachment(
      id: 1, guid: "g", filename: "photo.jpg", mimeType: "image/jpeg", size: 1000,
      isOutgoing: false, isSticker: false)
    XCTAssertTrue(renderer.canRender([a]))
  }

  func testCanRender_singleVideo_false() {
    let a = Attachment(
      id: 1, guid: "g", filename: "vid.mp4", mimeType: "video/mp4", size: 1000,
      isOutgoing: false, isSticker: false)
    XCTAssertFalse(renderer.canRender([a]))
  }

  func testCanRender_twoImages_false() {
    let a = Attachment(
      id: 1, guid: "g", filename: "photo.jpg", mimeType: "image/jpeg", size: 1000,
      isOutgoing: false, isSticker: false)
    XCTAssertFalse(renderer.canRender([a, a]))
  }

  func testCanRender_empty_false() {
    XCTAssertFalse(renderer.canRender([]))
  }
}
