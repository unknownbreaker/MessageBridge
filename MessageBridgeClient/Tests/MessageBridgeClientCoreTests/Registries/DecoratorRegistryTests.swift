import XCTest

@testable import MessageBridgeClientCore

final class DecoratorRegistryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    DecoratorRegistry.shared.reset()
  }
  override func tearDown() {
    DecoratorRegistry.shared.reset()
    super.tearDown()
  }

  func testShared_isSingleton() {
    XCTAssertTrue(DecoratorRegistry.shared === DecoratorRegistry.shared)
  }

  func testRegister_addsDecorator() {
    DecoratorRegistry.shared.register(MockBubbleDecorator(id: "a"))
    XCTAssertEqual(DecoratorRegistry.shared.all.count, 1)
  }

  func testReset_clears() {
    DecoratorRegistry.shared.register(MockBubbleDecorator(id: "a"))
    DecoratorRegistry.shared.reset()
    XCTAssertTrue(DecoratorRegistry.shared.all.isEmpty)
  }

  func testDecorators_filtersByPosition() {
    DecoratorRegistry.shared.register(MockBubbleDecorator(id: "below", position: .below))
    DecoratorRegistry.shared.register(MockBubbleDecorator(id: "top", position: .topTrailing))
    let msg = makeMessage()
    XCTAssertEqual(DecoratorRegistry.shared.decorators(for: msg, at: .below).count, 1)
    XCTAssertEqual(DecoratorRegistry.shared.decorators(for: msg, at: .below)[0].id, "below")
    XCTAssertEqual(DecoratorRegistry.shared.decorators(for: msg, at: .topTrailing).count, 1)
  }

  func testDecorators_filtersByShouldDecorate() {
    let show = MockBubbleDecorator(id: "show", position: .below)
    let hide = MockBubbleDecorator(id: "hide", position: .below)
    hide.shouldDecorateResult = false
    DecoratorRegistry.shared.register(show)
    DecoratorRegistry.shared.register(hide)
    let results = DecoratorRegistry.shared.decorators(for: makeMessage(), at: .below)
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results[0].id, "show")
  }

  func testDecorators_returnsMultipleAtSamePosition() {
    DecoratorRegistry.shared.register(MockBubbleDecorator(id: "a", position: .below))
    DecoratorRegistry.shared.register(MockBubbleDecorator(id: "b", position: .below))
    XCTAssertEqual(DecoratorRegistry.shared.decorators(for: makeMessage(), at: .below).count, 2)
  }

  func testDecorators_emptyForUnusedPosition() {
    DecoratorRegistry.shared.register(MockBubbleDecorator(id: "a", position: .below))
    XCTAssertTrue(DecoratorRegistry.shared.decorators(for: makeMessage(), at: .overlay).isEmpty)
  }

  private func makeMessage() -> Message {
    Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
  }
}
