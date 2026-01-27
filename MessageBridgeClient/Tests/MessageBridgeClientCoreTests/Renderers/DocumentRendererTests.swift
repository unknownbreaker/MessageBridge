import XCTest

@testable import MessageBridgeClientCore

final class DocumentRendererTests: XCTestCase {
  let renderer = DocumentRenderer()

  func testId() { XCTAssertEqual(renderer.id, "document") }
  func testPriority() { XCTAssertEqual(renderer.priority, 0) }
  func testCanRender_alwaysTrue() { XCTAssertTrue(renderer.canRender([])) }

  func testCanRender_withAttachment() {
    let a = Attachment(
      id: 1, guid: "g", filename: "file.pdf", mimeType: "application/pdf", size: 1000,
      isOutgoing: false, isSticker: false)
    XCTAssertTrue(renderer.canRender([a]))
  }
}
