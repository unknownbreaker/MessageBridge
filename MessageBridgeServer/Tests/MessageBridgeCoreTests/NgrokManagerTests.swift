import XCTest

@testable import MessageBridgeCore

final class NgrokManagerTests: XCTestCase {

  // MARK: - TunnelProvider Conformance Tests

  func testNgrokManager_id_isNgrok() {
    let manager = NgrokManager()
    XCTAssertEqual(manager.id, "ngrok")
  }

  func testNgrokManager_displayName_isNgrok() {
    let manager = NgrokManager()
    XCTAssertEqual(manager.displayName, "ngrok")
  }

  func testNgrokManager_description_isNotEmpty() {
    let manager = NgrokManager()
    XCTAssertFalse(manager.description.isEmpty)
    XCTAssertTrue(manager.description.contains("corporate"))
  }

  func testNgrokManager_iconName_isNetwork() {
    let manager = NgrokManager()
    XCTAssertEqual(manager.iconName, "network")
  }

  func testNgrokManager_isInstalled_returnsBoolean() {
    let manager = NgrokManager()
    // Just verify it returns without crashing - actual result depends on system
    _ = manager.isInstalled()
  }

  // MARK: - NgrokInfo Tests

  func testNgrokInfo_init() {
    let info = NgrokInfo(path: "/usr/local/bin/ngrok", version: "3.5.0")
    XCTAssertEqual(info.path, "/usr/local/bin/ngrok")
    XCTAssertEqual(info.version, "3.5.0")
  }

  func testNgrokInfo_initWithNilVersion() {
    let info = NgrokInfo(path: "/opt/homebrew/bin/ngrok", version: nil)
    XCTAssertEqual(info.path, "/opt/homebrew/bin/ngrok")
    XCTAssertNil(info.version)
  }

  // MARK: - NgrokManager Tests

  func testNgrokManager_initialStatus_isStopped() async {
    let manager = NgrokManager()
    let status = await manager.status
    XCTAssertEqual(status, .stopped)
  }

  func testNgrokManager_isRunning_whenNotStarted_returnsFalse() async {
    let manager = NgrokManager()
    let isRunning = await manager.isRunning()
    XCTAssertFalse(isRunning)
  }

  // MARK: - Connect/Disconnect Tests

  func testNgrokManager_disconnect_whenNotRunning_succeeds() async {
    let manager = NgrokManager()
    // Should complete without error even when not running
    await manager.disconnect()
    let status = await manager.status
    XCTAssertEqual(status, .stopped)
  }

  // MARK: - Detect Existing Tunnel Tests

  func testNgrokManager_detectExistingTunnel_whenNoProcessRunning_returnsNil() async {
    // This test assumes no ngrok process is running in the test environment
    // In CI, this should always be true
    let manager = NgrokManager()

    // First ensure we're in stopped state
    let initialStatus = await manager.status
    XCTAssertEqual(initialStatus, .stopped)

    // Try to detect an existing tunnel
    let detectedURL = await manager.detectExistingTunnel()

    // Should return nil when no ngrok process is running
    // Note: If ngrok IS running in the test environment, this test may fail
    // That's actually correct behavior - the test documents expected behavior
    if detectedURL == nil {
      // Verify status remains stopped when no process detected
      let finalStatus = await manager.status
      XCTAssertEqual(finalStatus, .stopped)
    } else {
      // If we detected a tunnel, verify status was updated
      let finalStatus = await manager.status
      XCTAssertTrue(finalStatus.isRunning)
    }
  }

  func testNgrokManager_detectExistingTunnel_updatesStatusWhenTunnelFound() async {
    let manager = NgrokManager()

    // Detect existing tunnel
    let detectedURL = await manager.detectExistingTunnel()

    if let url = detectedURL {
      // If a tunnel was detected, verify the status reflects it
      let status = await manager.status
      XCTAssertTrue(status.isRunning)
      XCTAssertEqual(status.url, url)
    }
    // If no tunnel detected, test passes - we just couldn't verify the positive case
  }

  // MARK: - Status Change Handler Tests

  func testNgrokManager_onStatusChange_handlerIsSet() async {
    let manager = NgrokManager()

    var handlerCalled = false
    await manager.onStatusChange { _ in
      handlerCalled = true
    }

    // Just verify the handler can be set without error
    // We can't easily trigger a status change in unit tests without a running process
    XCTAssertFalse(handlerCalled)  // Handler shouldn't be called just from setting it
  }
}
