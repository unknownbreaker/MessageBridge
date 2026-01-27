import XCTest

@testable import MessageBridgeClientCore

final class LargeEmojiRendererTests: XCTestCase {
  let renderer = LargeEmojiRenderer()

  func testId_isLargeEmoji() {
    XCTAssertEqual(renderer.id, "large-emoji")
  }

  func testPriority_is50() {
    XCTAssertEqual(renderer.priority, 50)
  }

  func testCanRender_singleEmoji_returnsTrue() {
    XCTAssertTrue(renderer.canRender(makeMessage("😀")))
  }

  func testCanRender_twoEmojis_returnsTrue() {
    XCTAssertTrue(renderer.canRender(makeMessage("😀🎉")))
  }

  func testCanRender_threeEmojis_returnsTrue() {
    XCTAssertTrue(renderer.canRender(makeMessage("😀🎉🔥")))
  }

  func testCanRender_fourEmojis_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage("😀🎉🔥❤️")))
  }

  func testCanRender_textWithEmoji_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage("Hello 😀")))
  }

  func testCanRender_plainText_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage("Hello world")))
  }

  func testCanRender_nilText_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage(nil)))
  }

  func testCanRender_emptyText_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage("")))
  }

  func testCanRender_numbersOnly_returnsFalse() {
    XCTAssertFalse(renderer.canRender(makeMessage("123")))
  }

  private func makeMessage(_ text: String?) -> Message {
    Message(
      id: 1, guid: "g1", text: text, date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
  }
}
