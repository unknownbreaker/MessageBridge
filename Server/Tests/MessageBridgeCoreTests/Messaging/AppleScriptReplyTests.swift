import XCTest

@testable import MessageBridgeCore

final class AppleScriptReplyTests: XCTestCase {
  let sender = AppleScriptMessageSender()

  func testBuildReplyAppleScript_containsOriginalMessageText() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "Thanks!",
      replyToText: "Original message here",
      service: "iMessage"
    )
    XCTAssertTrue(script.contains("Original message here"))
    XCTAssertTrue(script.contains("Thanks!"))
  }

  func testBuildReplyAppleScript_escapesQuotes() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "He said \"hello\"",
      replyToText: "What's up?",
      service: "iMessage"
    )
    XCTAssertTrue(script.contains("\\\""))
  }

  func testBuildReplyAppleScript_usesSystemEvents() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "Reply text",
      replyToText: "Original",
      service: "iMessage"
    )
    XCTAssertTrue(script.contains("System Events"))
    XCTAssertTrue(script.contains("Reply"))
  }
}
