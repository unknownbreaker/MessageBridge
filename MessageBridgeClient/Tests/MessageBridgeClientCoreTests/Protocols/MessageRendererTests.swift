import XCTest

@testable import MessageBridgeClientCore

final class MessageRendererTests: XCTestCase {
  func testMockRenderer_hasId() {
    let renderer = MockMessageRenderer(id: "test-renderer")
    XCTAssertEqual(renderer.id, "test-renderer")
  }

  func testMockRenderer_hasPriority() {
    let renderer = MockMessageRenderer(priority: 50)
    XCTAssertEqual(renderer.priority, 50)
  }

  func testMockRenderer_canRender_returnsConfiguredValue() {
    let message = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    let renderer = MockMessageRenderer()
    renderer.canRenderResult = false
    XCTAssertFalse(renderer.canRender(message))
    renderer.canRenderResult = true
    XCTAssertTrue(renderer.canRender(message))
  }

  func testMockRenderer_canRender_incrementsCallCount() {
    let message = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    let renderer = MockMessageRenderer()
    _ = renderer.canRender(message)
    _ = renderer.canRender(message)
    XCTAssertEqual(renderer.canRenderCallCount, 2)
  }
}
