import XCTest

@testable import MessageBridgeClientCore

final class BubbleDecoratorTests: XCTestCase {
  let context = DecoratorContext(
    isLastSentMessage: false, isLastMessage: false, conversationId: "c1")

  func testMock_hasId() {
    XCTAssertEqual(MockBubbleDecorator(id: "test").id, "test")
  }

  func testMock_hasPosition() {
    XCTAssertEqual(MockBubbleDecorator(position: .topTrailing).position, .topTrailing)
  }

  func testMock_shouldDecorate_returnsConfiguredValue() {
    let mock = MockBubbleDecorator()
    let msg = makeMessage()
    mock.shouldDecorateResult = false
    XCTAssertFalse(mock.shouldDecorate(msg, context: context))
    mock.shouldDecorateResult = true
    XCTAssertTrue(mock.shouldDecorate(msg, context: context))
  }

  func testDecoratorPosition_allCasesExist() {
    _ = DecoratorPosition.topLeading
    _ = DecoratorPosition.topTrailing
    _ = DecoratorPosition.bottomLeading
    _ = DecoratorPosition.bottomTrailing
    _ = DecoratorPosition.below
    _ = DecoratorPosition.overlay
  }

  private func makeMessage() -> Message {
    Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
  }
}
