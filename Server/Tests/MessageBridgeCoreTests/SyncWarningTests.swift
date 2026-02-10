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

  func testBuildSearchScript_containsSafetyChecks() {
    let script = ChatDatabase.buildSearchScript(searchString: "Test Chat")

    // Should find search field via accessibility role, not Cmd+F
    XCTAssertTrue(script.contains("AXSearchField"), "Script should find search field by role")
    XCTAssertTrue(script.contains("click searchField"), "Script should click to focus search field")
    XCTAssertFalse(
      script.contains("keystroke \"f\" using command down"),
      "Script should NOT use Cmd+F (unreliable, can type into compose field)")

    // Should verify text reached the search field before proceeding
    XCTAssertTrue(
      script.contains("textConfirmed"), "Script should verify text went to search field")
    XCTAssertTrue(script.contains("wrong_field"), "Script should detect wrong field")

    // Should return no_search_field if search field not found
    XCTAssertTrue(
      script.contains("no_search_field"), "Script should handle missing search field")

    XCTAssertTrue(script.contains("Test Chat"), "Script should contain search string")
    XCTAssertTrue(script.contains("Conversations"), "Script should check for results")
  }

  func testBuildSearchScript_escapesSpecialCharacters() {
    let script = ChatDatabase.buildSearchScript(searchString: "Chat \"With\" Quotes\\Slash")

    XCTAssertTrue(
      script.contains("Chat \\\"With\\\" Quotes\\\\Slash"),
      "Script should escape quotes and backslashes")
  }
}
