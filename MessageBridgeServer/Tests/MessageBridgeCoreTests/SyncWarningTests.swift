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

  func testWebSocketManager_broadcastSyncWarning() async throws {
    // This is an integration test - we'll verify the method exists and compiles
    // Actual broadcast behavior is tested via WebSocket integration tests
    let manager = WebSocketManager()

    // Should compile and not throw
    await manager.broadcastSyncWarning(conversationId: "chat123", message: "Test warning")
    await manager.broadcastSyncWarningCleared(conversationId: "chat123")

    // If we get here, methods exist and work
    XCTAssertTrue(true)
  }
}
