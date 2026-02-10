import XCTest

@testable import MessageBridgeClientCore

final class AttachmentRendererTests: XCTestCase {
  func testMockRenderer_hasId() {
    let renderer = MockAttachmentRenderer(id: "test")
    XCTAssertEqual(renderer.id, "test")
  }

  func testMockRenderer_hasPriority() {
    let renderer = MockAttachmentRenderer(priority: 50)
    XCTAssertEqual(renderer.priority, 50)
  }

  func testMockRenderer_canRender_returnsConfiguredValue() {
    let renderer = MockAttachmentRenderer()
    renderer.canRenderResult = false
    XCTAssertFalse(renderer.canRender([]))
    renderer.canRenderResult = true
    XCTAssertTrue(renderer.canRender([]))
  }

  func testMockRenderer_canRender_incrementsCallCount() {
    let renderer = MockAttachmentRenderer()
    _ = renderer.canRender([])
    _ = renderer.canRender([])
    XCTAssertEqual(renderer.canRenderCallCount, 2)
  }
}
