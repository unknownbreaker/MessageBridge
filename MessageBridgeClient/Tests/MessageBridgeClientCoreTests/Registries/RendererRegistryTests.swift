import XCTest

@testable import MessageBridgeClientCore

final class RendererRegistryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    RendererRegistry.shared.reset()
  }

  override func tearDown() {
    RendererRegistry.shared.reset()
    super.tearDown()
  }

  func testShared_isSingleton() {
    let a = RendererRegistry.shared
    let b = RendererRegistry.shared
    XCTAssertTrue(a === b)
  }

  func testRegister_addsRenderer() {
    let renderer = MockMessageRenderer(id: "test")
    RendererRegistry.shared.register(renderer)
    XCTAssertEqual(RendererRegistry.shared.all.count, 1)
  }

  func testAll_returnsRegisteredRenderers() {
    RendererRegistry.shared.register(MockMessageRenderer(id: "a"))
    RendererRegistry.shared.register(MockMessageRenderer(id: "b"))
    let ids = RendererRegistry.shared.all.map { $0.id }
    XCTAssertTrue(ids.contains("a"))
    XCTAssertTrue(ids.contains("b"))
  }

  func testReset_clearsAllRenderers() {
    RendererRegistry.shared.register(MockMessageRenderer(id: "test"))
    RendererRegistry.shared.reset()
    XCTAssertTrue(RendererRegistry.shared.all.isEmpty)
  }

  func testRenderer_selectsHighestPriorityMatch() {
    let low = MockMessageRenderer(id: "low", priority: 0)
    let high = MockMessageRenderer(id: "high", priority: 100)
    RendererRegistry.shared.register(low)
    RendererRegistry.shared.register(high)

    let message = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    let selected = RendererRegistry.shared.renderer(for: message)
    XCTAssertEqual(selected.id, "high")
  }

  func testRenderer_skipsNonMatching() {
    let noMatch = MockMessageRenderer(id: "no-match", priority: 100)
    noMatch.canRenderResult = false
    let fallback = MockMessageRenderer(id: "fallback", priority: 0)
    RendererRegistry.shared.register(noMatch)
    RendererRegistry.shared.register(fallback)

    let message = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    let selected = RendererRegistry.shared.renderer(for: message)
    XCTAssertEqual(selected.id, "fallback")
  }

  func testRenderer_emptyRegistry_returnsPlainTextRenderer() {
    let message = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    let selected = RendererRegistry.shared.renderer(for: message)
    XCTAssertEqual(selected.id, "plain-text")
  }
}
