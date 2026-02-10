import XCTest

@testable import MessageBridgeClientCore

final class AttachmentRendererRegistryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    AttachmentRendererRegistry.shared.reset()
  }

  override func tearDown() {
    AttachmentRendererRegistry.shared.reset()
    super.tearDown()
  }

  func testShared_isSingleton() {
    XCTAssertTrue(AttachmentRendererRegistry.shared === AttachmentRendererRegistry.shared)
  }

  func testRegister_addsRenderer() {
    AttachmentRendererRegistry.shared.register(MockAttachmentRenderer(id: "a"))
    XCTAssertEqual(AttachmentRendererRegistry.shared.all.count, 1)
  }

  func testAll_returnsRegistered() {
    AttachmentRendererRegistry.shared.register(MockAttachmentRenderer(id: "a"))
    AttachmentRendererRegistry.shared.register(MockAttachmentRenderer(id: "b"))
    let ids = AttachmentRendererRegistry.shared.all.map { $0.id }
    XCTAssertTrue(ids.contains("a"))
    XCTAssertTrue(ids.contains("b"))
  }

  func testReset_clears() {
    AttachmentRendererRegistry.shared.register(MockAttachmentRenderer(id: "a"))
    AttachmentRendererRegistry.shared.reset()
    XCTAssertTrue(AttachmentRendererRegistry.shared.all.isEmpty)
  }

  func testRenderer_selectsHighestPriorityMatch() {
    let low = MockAttachmentRenderer(id: "low", priority: 0)
    let high = MockAttachmentRenderer(id: "high", priority: 100)
    AttachmentRendererRegistry.shared.register(low)
    AttachmentRendererRegistry.shared.register(high)
    let selected = AttachmentRendererRegistry.shared.renderer(for: [])
    XCTAssertEqual(selected.id, "high")
  }

  func testRenderer_skipsNonMatching() {
    let noMatch = MockAttachmentRenderer(id: "no", priority: 100)
    noMatch.canRenderResult = false
    let fallback = MockAttachmentRenderer(id: "fall", priority: 0)
    AttachmentRendererRegistry.shared.register(noMatch)
    AttachmentRendererRegistry.shared.register(fallback)
    let selected = AttachmentRendererRegistry.shared.renderer(for: [])
    XCTAssertEqual(selected.id, "fall")
  }

  func testRenderer_emptyRegistry_returnsDocumentRenderer() {
    let selected = AttachmentRendererRegistry.shared.renderer(for: [])
    XCTAssertEqual(selected.id, "document")
  }
}
