import XCTest

@testable import MessageBridgeCore

final class SyncWarningTests: XCTestCase {
  func testSyncWarningEvent_encodesCorrectly() throws {
    let event = SyncWarningEvent(
      conversationId: "chat123",
      message: "Read status could not be synced"
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    XCTAssertEqual(json["conversationId"] as? String, "chat123")
    XCTAssertEqual(json["message"] as? String, "Read status could not be synced")
  }

  func testSyncWarningClearedEvent_encodesCorrectly() throws {
    let event = SyncWarningClearedEvent(conversationId: "chat123")

    let encoder = JSONEncoder()
    let data = try encoder.encode(event)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    XCTAssertEqual(json["conversationId"] as? String, "chat123")
  }

  func testWebSocketMessageType_includesSyncWarning() {
    XCTAssertEqual(WebSocketMessageType.syncWarning.rawValue, "sync_warning")
    XCTAssertEqual(WebSocketMessageType.syncWarningCleared.rawValue, "sync_warning_cleared")
  }
}
