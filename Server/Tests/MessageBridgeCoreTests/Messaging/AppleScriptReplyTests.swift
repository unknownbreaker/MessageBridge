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

  func testBuildReplyAppleScript_usesDirectReplyAction() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "Reply text",
      replyToText: "Original",
      service: "iMessage"
    )
    // Must use the direct "Reply…" action (Unicode ellipsis U+2026), not AXShowMenu
    XCTAssertTrue(
      script.contains("Reply\u{2026}"), "Script should use the direct Reply\u{2026} action")
    XCTAssertFalse(script.contains("AXShowMenu"), "Script should NOT use AXShowMenu context menu")
  }

  func testBuildReplyAppleScript_searchesValueProperty() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "Reply text",
      replyToText: "Original",
      service: "iMessage"
    )
    // Must search the value property (where message text lives in AXTextArea)
    XCTAssertTrue(
      script.contains("value of elem"),
      "Script should search the value property of elements"
    )
    // Must NOT search description (old behavior)
    XCTAssertFalse(
      script.contains("description of elem"),
      "Script should NOT search the description property"
    )
  }

  func testBuildReplyAppleScript_usesGroup1NotSplitterGroup() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "Reply text",
      replyToText: "Original",
      service: "iMessage"
    )
    // macOS 26.2: no splitter group, messages live under group 1 of window 1
    XCTAssertTrue(
      script.contains("entire contents of group 1"),
      "Script should scan entire contents of group 1"
    )
    XCTAssertFalse(
      script.contains("splitter group"),
      "Script should NOT reference splitter group"
    )
  }

  func testBuildReplyAppleScript_findsLastMatchingElement() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "Reply text",
      replyToText: "Duplicate message",
      service: "iMessage"
    )
    // The script should NOT use early-exit (exit repeat) when scanning,
    // so it picks the last matching element (most recent message)
    let valueCheckRange = script.range(of: "value of elem contains")
    XCTAssertNotNil(valueCheckRange, "Script should check value of elem")

    // Verify no early exit after the value check — the foundElement assignment
    // should NOT be followed by "exit repeat"
    XCTAssertFalse(
      script.contains("exit repeat"),
      "Script should NOT use exit repeat; it should find the last matching element"
    )
  }

  func testBuildReplyAppleScript_escapesBackslashes() {
    let script = sender.buildReplyAppleScript(
      recipient: "chat123",
      text: "Path is C:\\Users",
      replyToText: "Check C:\\Temp",
      service: "iMessage"
    )
    // Backslashes should be doubled for AppleScript string escaping
    XCTAssertTrue(script.contains("C:\\\\Users"))
    XCTAssertTrue(script.contains("C:\\\\Temp"))
  }

  // MARK: - fetchMessageText via MockChatDatabase

  func testFetchMessageText_returnsTextForKnownGuid() async throws {
    let mockDB = MockChatDatabase()
    mockDB.messageTextToReturn = "Hello world"
    let text = try await mockDB.fetchMessageText(byGuid: "msg-001")
    XCTAssertEqual(text, "Hello world")
  }

  func testFetchMessageText_returnsNilForUnknownGuid() async throws {
    let mockDB = MockChatDatabase()
    mockDB.messageTextToReturn = nil
    let text = try await mockDB.fetchMessageText(byGuid: "nonexistent")
    XCTAssertNil(text)
  }
}
