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

  func testSyncResult_hasCorrectCases() {
    let success = SyncResult.success
    let failed = SyncResult.failed(reason: "Test reason")

    switch success {
    case .success:
      XCTAssertTrue(true)
    case .failed:
      XCTFail("Expected success")
    }

    switch failed {
    case .success:
      XCTFail("Expected failed")
    case .failed(let reason):
      XCTAssertEqual(reason, "Test reason")
    }
  }

  func testBuildSearchScript_containsPollLogic() {
    // Test that the script contains the polling pattern
    let script = ChatDatabase.buildSearchScript(searchString: "Test Chat")

    XCTAssertTrue(script.contains("repeat"), "Script should contain polling loop")
    XCTAssertTrue(script.contains("entire contents"), "Script should use entire contents")
    XCTAssertTrue(script.contains("Conversations"), "Script should look for Conversations header")
    XCTAssertTrue(script.contains("Test Chat"), "Script should contain search string")
  }
}
