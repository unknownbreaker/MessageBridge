import XCTest

@testable import MessageBridgeClientCore

final class VideoRendererTests: XCTestCase {
  let renderer = VideoRenderer()

  func testId() { XCTAssertEqual(renderer.id, "video") }
  func testPriority() { XCTAssertEqual(renderer.priority, 50) }

  func testCanRender_singleVideo_true() {
    let a = Attachment(
      id: 1, guid: "g", filename: "vid.mp4", mimeType: "video/mp4", size: 5000,
      isOutgoing: false, isSticker: false)
    XCTAssertTrue(renderer.canRender([a]))
  }

  func testCanRender_multipleVideos_true() {
    let a = Attachment(
      id: 1, guid: "g", filename: "vid.mp4", mimeType: "video/mp4", size: 5000,
      isOutgoing: false, isSticker: false)
    XCTAssertTrue(renderer.canRender([a, a]))
  }

  func testCanRender_image_false() {
    let a = Attachment(
      id: 1, guid: "g", filename: "photo.jpg", mimeType: "image/jpeg", size: 1000,
      isOutgoing: false, isSticker: false)
    XCTAssertFalse(renderer.canRender([a]))
  }

  func testCanRender_mixed_false() {
    let video = Attachment(
      id: 1, guid: "g", filename: "vid.mp4", mimeType: "video/mp4", size: 5000,
      isOutgoing: false, isSticker: false)
    let image = Attachment(
      id: 2, guid: "g2", filename: "photo.jpg", mimeType: "image/jpeg", size: 1000,
      isOutgoing: false, isSticker: false)
    XCTAssertFalse(renderer.canRender([video, image]))
  }

  func testCanRender_empty_false() {
    XCTAssertFalse(renderer.canRender([]))
  }
}
