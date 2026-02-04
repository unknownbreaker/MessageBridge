import XCTest

@testable import MessageBridgeClientCore

final class SyncWarningModelTests: XCTestCase {
  func testSyncWarningEvent_decodesCorrectly() throws {
    let json = """
      {"conversationId": "chat123", "message": "Read status could not be synced"}
      """
    let data = json.data(using: .utf8)!

    let event = try JSONDecoder().decode(SyncWarningEvent.self, from: data)

    XCTAssertEqual(event.conversationId, "chat123")
    XCTAssertEqual(event.message, "Read status could not be synced")
  }

  func testSyncWarningClearedEvent_decodesCorrectly() throws {
    let json = """
      {"conversationId": "chat123"}
      """
    let data = json.data(using: .utf8)!

    let event = try JSONDecoder().decode(SyncWarningClearedEvent.self, from: data)

    XCTAssertEqual(event.conversationId, "chat123")
  }

  func testSyncWarningEvent_encodesCorrectly() throws {
    let event = SyncWarningEvent(
      conversationId: "chat456",
      message: "Test warning message"
    )

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(SyncWarningEvent.self, from: data)

    XCTAssertEqual(decoded.conversationId, "chat456")
    XCTAssertEqual(decoded.message, "Test warning message")
  }

  func testSyncWarningClearedEvent_encodesCorrectly() throws {
    let event = SyncWarningClearedEvent(conversationId: "chat789")

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(SyncWarningClearedEvent.self, from: data)

    XCTAssertEqual(decoded.conversationId, "chat789")
  }
}
