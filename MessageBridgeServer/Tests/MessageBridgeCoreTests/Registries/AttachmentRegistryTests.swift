import XCTest

@testable import MessageBridgeCore

final class AttachmentRegistryTests: XCTestCase {

  override func setUp() {
    super.setUp()
    AttachmentRegistry.shared.reset()
  }

  override func tearDown() {
    AttachmentRegistry.shared.reset()
    super.tearDown()
  }

  func testRegister_addsHandler() {
    let handler = MockAttachmentHandler(id: "test")
    AttachmentRegistry.shared.register(handler)

    XCTAssertEqual(AttachmentRegistry.shared.all.count, 1)
  }

  func testHandler_forExactMimeType_returnsHandler() {
    let handler = MockAttachmentHandler(
      id: "video",
      supportedMimeTypes: ["video/mp4"]
    )
    AttachmentRegistry.shared.register(handler)

    let found = AttachmentRegistry.shared.handler(for: "video/mp4")
    XCTAssertNotNil(found)
    XCTAssertEqual(found?.id, "video")
  }

  func testHandler_forWildcardMimeType_returnsHandler() {
    let handler = MockAttachmentHandler(
      id: "image",
      supportedMimeTypes: ["image/*"]
    )
    AttachmentRegistry.shared.register(handler)

    let foundJpeg = AttachmentRegistry.shared.handler(for: "image/jpeg")
    XCTAssertNotNil(foundJpeg)
    XCTAssertEqual(foundJpeg?.id, "image")

    let foundPng = AttachmentRegistry.shared.handler(for: "image/png")
    XCTAssertNotNil(foundPng)
    XCTAssertEqual(foundPng?.id, "image")
  }

  func testHandler_forUnknownMimeType_returnsNil() {
    let handler = MockAttachmentHandler(
      id: "image",
      supportedMimeTypes: ["image/*"]
    )
    AttachmentRegistry.shared.register(handler)

    let found = AttachmentRegistry.shared.handler(for: "audio/mp3")
    XCTAssertNil(found)
  }

  func testHandler_withMultipleHandlers_returnsFirstMatch() {
    let imageHandler = MockAttachmentHandler(
      id: "image-generic",
      supportedMimeTypes: ["image/*"]
    )
    let jpegHandler = MockAttachmentHandler(
      id: "jpeg-specific",
      supportedMimeTypes: ["image/jpeg"]
    )

    // Register generic first, then specific
    AttachmentRegistry.shared.register(imageHandler)
    AttachmentRegistry.shared.register(jpegHandler)

    // First registered match wins
    let found = AttachmentRegistry.shared.handler(for: "image/jpeg")
    XCTAssertEqual(found?.id, "image-generic")
  }

  func testAll_returnsAllHandlers() {
    let handler1 = MockAttachmentHandler(id: "h1")
    let handler2 = MockAttachmentHandler(id: "h2")

    AttachmentRegistry.shared.register(handler1)
    AttachmentRegistry.shared.register(handler2)

    let all = AttachmentRegistry.shared.all
    XCTAssertEqual(all.count, 2)
  }

  func testReset_removesAllHandlers() {
    AttachmentRegistry.shared.register(MockAttachmentHandler(id: "h1"))
    AttachmentRegistry.shared.register(MockAttachmentHandler(id: "h2"))
    XCTAssertEqual(AttachmentRegistry.shared.all.count, 2)

    AttachmentRegistry.shared.reset()
    XCTAssertEqual(AttachmentRegistry.shared.all.count, 0)
  }

  func testMimeTypeMatches_exactMatch_returnsTrue() {
    let handler = MockAttachmentHandler(
      id: "specific",
      supportedMimeTypes: ["video/mp4"]
    )
    AttachmentRegistry.shared.register(handler)

    XCTAssertNotNil(AttachmentRegistry.shared.handler(for: "video/mp4"))
    XCTAssertNil(AttachmentRegistry.shared.handler(for: "video/quicktime"))
  }

  func testMimeTypeMatches_wildcardDoesNotMatchDifferentType() {
    let handler = MockAttachmentHandler(
      id: "image",
      supportedMimeTypes: ["image/*"]
    )
    AttachmentRegistry.shared.register(handler)

    XCTAssertNil(AttachmentRegistry.shared.handler(for: "video/mp4"))
    XCTAssertNil(AttachmentRegistry.shared.handler(for: "imagejpeg"))  // Malformed
  }
}
