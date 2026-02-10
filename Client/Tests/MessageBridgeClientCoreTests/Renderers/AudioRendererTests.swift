import XCTest

@testable import MessageBridgeClientCore

final class AudioRendererTests: XCTestCase {
  let renderer = AudioRenderer()

  func testId() { XCTAssertEqual(renderer.id, "audio") }
  func testPriority() { XCTAssertEqual(renderer.priority, 50) }

  func testCanRender_singleAudio_true() {
    let a = Attachment(
      id: 1, guid: "g", filename: "audio.mp3", mimeType: "audio/mpeg", size: 2000,
      isOutgoing: false, isSticker: false)
    XCTAssertTrue(renderer.canRender([a]))
  }

  func testCanRender_multipleAudio_true() {
    let a = Attachment(
      id: 1, guid: "g", filename: "audio.mp3", mimeType: "audio/mpeg", size: 2000,
      isOutgoing: false, isSticker: false)
    XCTAssertTrue(renderer.canRender([a, a]))
  }

  func testCanRender_image_false() {
    let a = Attachment(
      id: 1, guid: "g", filename: "photo.jpg", mimeType: "image/jpeg", size: 1000,
      isOutgoing: false, isSticker: false)
    XCTAssertFalse(renderer.canRender([a]))
  }

  func testCanRender_empty_false() {
    XCTAssertFalse(renderer.canRender([]))
  }
}
