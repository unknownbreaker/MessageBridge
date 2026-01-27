import XCTest

@testable import MessageBridgeClientCore

/// Blind audit tests for M1.2 (Basic Client) + M1.3 (Composer).
/// Written from spec.md acceptance criteria without reading implementation.
final class ClientViewAuditTests: XCTestCase {

  // MARK: - M1.2: Conversation Model

  /// Spec: "Conversation list shows contact name, last message preview, date"
  func testConversation_hasDisplayName() {
    let convo = Conversation(
      id: "c1", guid: "g1", displayName: "Alice",
      participants: [], lastMessage: nil, isGroup: false)
    XCTAssertEqual(convo.displayName, "Alice")
  }

  /// Spec: "Conversation list shows contact name, last message preview, date"
  func testConversation_hasLastMessage() {
    let msg = Message(
      id: 1, guid: "m1", text: "Hey", date: Date(),
      isFromMe: false, handleId: nil, conversationId: "c1")
    let convo = Conversation(
      id: "c1", guid: "g1", displayName: "Alice",
      participants: [], lastMessage: msg, isGroup: false)
    XCTAssertNotNil(convo.lastMessage)
    XCTAssertEqual(convo.lastMessage?.text, "Hey")
  }

  /// Spec: "Conversation list shows contact name, last message preview, date"
  func testMessage_hasDate() {
    let now = Date()
    let msg = Message(
      id: 1, guid: "m1", text: "Hello", date: now,
      isFromMe: false, handleId: nil, conversationId: "c1")
    XCTAssertEqual(msg.date, now)
  }

  // MARK: - M1.2: Message Model

  /// Spec: "Message thread shows bubbles with sent/received styling"
  func testMessage_hasText() {
    let msg = Message(
      id: 1, guid: "m1", text: "Hello", date: Date(),
      isFromMe: false, handleId: nil, conversationId: "c1")
    XCTAssertEqual(msg.text, "Hello")
  }

  /// Spec: "Message thread shows bubbles with sent/received styling"
  func testMessage_isFromMe_distinguishesSentReceived() {
    let sent = Message(
      id: 1, guid: "m1", text: "Sent", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1")
    let received = Message(
      id: 2, guid: "m2", text: "Received", date: Date(),
      isFromMe: false, handleId: nil, conversationId: "c1")
    XCTAssertTrue(sent.isFromMe)
    XCTAssertFalse(received.isFromMe)
  }

  /// Spec: "Message thread shows bubbles with sent/received styling"
  func testMessage_hasSender() {
    let msg = Message(
      id: 1, guid: "m1", text: "Hello", date: Date(),
      isFromMe: false, handleId: 42, conversationId: "c1")
    XCTAssertEqual(msg.handleId, 42)
  }

  // MARK: - M1.3: Composer Infrastructure

  /// Spec: "Composer text field at bottom of message thread"
  func testSubmitEvent_exists() {
    let _: SubmitEvent = .enter
    let _: SubmitEvent = .shiftEnter
    let _: SubmitEvent = .commandEnter
    let _: SubmitEvent = .optionEnter
  }

  /// Spec: "Enter sends message (configurable)"
  func testComposerPlugin_protocolExists() {
    let _: (any ComposerPlugin).Type = (any ComposerPlugin).self
  }
}

// MARK: - Audit Findings (2026-01-27)
//
// Build attempt 1: FAILED — `any ComposerPlugin.Protocol` syntax error.
//   Fix: Changed to `(any ComposerPlugin).Type` — compiled.
//
// Build attempt 2: PASSED — all 8 tests compiled and passed.
//
// Findings:
//   ✅ Conversation has displayName, lastMessage, isGroup — matches spec M1.2
//   ✅ Message has id, guid, text, date, isFromMe, handleId, conversationId — matches spec M1.2
//   ✅ SubmitEvent enum exists with .enter, .shiftEnter, .commandEnter, .optionEnter — matches spec M1.3
//   ✅ ComposerPlugin protocol exists and is importable — matches spec M1.3
//
// All 8 tests: PASSED (0 failures)
