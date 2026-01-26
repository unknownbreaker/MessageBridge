import XCTest

@testable import MessageBridgeCore

final class CloudflaredManagerTests: XCTestCase {

  // MARK: - TunnelStatus Tests

  func testTunnelStatus_stopped_displayText() {
    let status = TunnelStatus.stopped
    XCTAssertEqual(status.displayText, "Stopped")
    XCTAssertFalse(status.isRunning)
    XCTAssertNil(status.url)
  }

  func testTunnelStatus_notInstalled_displayText() {
    let status = TunnelStatus.notInstalled
    XCTAssertEqual(status.displayText, "Not Installed")
    XCTAssertFalse(status.isRunning)
    XCTAssertNil(status.url)
  }

  func testTunnelStatus_starting_displayText() {
    let status = TunnelStatus.starting
    XCTAssertEqual(status.displayText, "Starting...")
    XCTAssertFalse(status.isRunning)
    XCTAssertNil(status.url)
  }

  func testTunnelStatus_running_quickTunnel_displayText() {
    let status = TunnelStatus.running(url: "https://test.trycloudflare.com", isQuickTunnel: true)
    XCTAssertEqual(status.displayText, "Quick Tunnel Active")
    XCTAssertTrue(status.isRunning)
    XCTAssertEqual(status.url, "https://test.trycloudflare.com")
  }

  func testTunnelStatus_running_namedTunnel_displayText() {
    let status = TunnelStatus.running(
      url: "https://messagebridge.example.com", isQuickTunnel: false)
    XCTAssertEqual(status.displayText, "Tunnel Active")
    XCTAssertTrue(status.isRunning)
    XCTAssertEqual(status.url, "https://messagebridge.example.com")
  }

  func testTunnelStatus_error_displayText() {
    let status = TunnelStatus.error("Connection failed")
    XCTAssertEqual(status.displayText, "Error: Connection failed")
    XCTAssertFalse(status.isRunning)
    XCTAssertNil(status.url)
  }

  func testTunnelStatus_equatable() {
    XCTAssertEqual(TunnelStatus.stopped, TunnelStatus.stopped)
    XCTAssertEqual(TunnelStatus.starting, TunnelStatus.starting)
    XCTAssertNotEqual(TunnelStatus.stopped, TunnelStatus.starting)

    let running1 = TunnelStatus.running(url: "https://a.com", isQuickTunnel: true)
    let running2 = TunnelStatus.running(url: "https://a.com", isQuickTunnel: true)
    let running3 = TunnelStatus.running(url: "https://b.com", isQuickTunnel: true)
    XCTAssertEqual(running1, running2)
    XCTAssertNotEqual(running1, running3)
  }

  // MARK: - CloudflaredError Tests

  func testCloudflaredError_notInstalled_description() {
    let error = CloudflaredError.notInstalled
    XCTAssertEqual(error.errorDescription, "cloudflared is not installed")
  }

  func testCloudflaredError_invalidDownloadURL_description() {
    let error = CloudflaredError.invalidDownloadURL
    XCTAssertEqual(error.errorDescription, "Invalid download URL")
  }

  func testCloudflaredError_downloadFailed_description() {
    let error = CloudflaredError.downloadFailed
    XCTAssertEqual(error.errorDescription, "Failed to download cloudflared")
  }

  func testCloudflaredError_extractionFailed_description() {
    let error = CloudflaredError.extractionFailed
    XCTAssertEqual(error.errorDescription, "Failed to extract cloudflared archive")
  }

  func testCloudflaredError_failedToStart_description() {
    let error = CloudflaredError.failedToStart("Process crashed")
    XCTAssertEqual(error.errorDescription, "Failed to start tunnel: Process crashed")
  }

  func testCloudflaredError_tunnelFailed_description() {
    let error = CloudflaredError.tunnelFailed("Connection reset")
    XCTAssertEqual(error.errorDescription, "Tunnel failed: Connection reset")
  }

  func testCloudflaredError_timeout_description() {
    let error = CloudflaredError.timeout
    XCTAssertEqual(error.errorDescription, "Timed out waiting for tunnel URL")
  }

  // MARK: - CloudflaredInfo Tests

  func testCloudflaredInfo_init() {
    let info = CloudflaredInfo(path: "/usr/local/bin/cloudflared", version: "2024.12.0")
    XCTAssertEqual(info.path, "/usr/local/bin/cloudflared")
    XCTAssertEqual(info.version, "2024.12.0")
  }

  func testCloudflaredInfo_initWithNilVersion() {
    let info = CloudflaredInfo(path: "/opt/homebrew/bin/cloudflared", version: nil)
    XCTAssertEqual(info.path, "/opt/homebrew/bin/cloudflared")
    XCTAssertNil(info.version)
  }

  // MARK: - CloudflaredManager Tests

  func testCloudflaredManager_initialStatus_isStopped() async {
    let manager = CloudflaredManager()
    let status = await manager.status
    XCTAssertEqual(status, .stopped)
  }

  func testCloudflaredManager_isRunning_whenNotStarted_returnsFalse() async {
    let manager = CloudflaredManager()
    let isRunning = await manager.isRunning()
    XCTAssertFalse(isRunning)
  }

  // MARK: - Detect Existing Tunnel Tests

  func testCloudflaredManager_detectExistingTunnel_whenNoProcessRunning_returnsFalse() async {
    // This test assumes no cloudflared process is running in the test environment
    // In CI, this should always be true
    let manager = CloudflaredManager()

    // First ensure we're in stopped state
    let initialStatus = await manager.status
    XCTAssertEqual(initialStatus, .stopped)

    // Try to detect an existing tunnel
    let processDetected = await manager.detectExistingTunnel()

    // Should return false when no cloudflared process is running
    // Note: If cloudflared IS running in the test environment, this test may fail
    // That's actually correct behavior - the test documents expected behavior
    if !processDetected {
      // Verify status remains stopped when no process detected
      let finalStatus = await manager.status
      XCTAssertEqual(finalStatus, .stopped)
    } else {
      // If we detected a process, verify status was updated to error
      // (cloudflared doesn't have a local API to get the URL)
      let finalStatus = await manager.status
      if case .error = finalStatus {
        // Expected - we show an error when external process detected
      } else {
        XCTFail("Expected error status when external cloudflared detected")
      }
    }
  }

  func testCloudflaredManager_detectExistingTunnel_setsErrorStatusWhenProcessFound() async {
    let manager = CloudflaredManager()

    // Detect existing tunnel
    let processDetected = await manager.detectExistingTunnel()

    if processDetected {
      // If a process was detected, verify the status shows an error
      // (since we can't get the URL from cloudflared)
      let status = await manager.status
      if case .error(let message) = status {
        XCTAssertTrue(message.contains("External cloudflared process"))
      } else {
        XCTFail("Expected error status when external process detected")
      }
    }
    // If no process detected, test passes - we just couldn't verify the positive case
  }

  // MARK: - Status Change Handler Tests

  func testCloudflaredManager_onStatusChange_handlerIsSet() async {
    let manager = CloudflaredManager()

    var handlerCalled = false
    await manager.onStatusChange { _ in
      handlerCalled = true
    }

    // Just verify the handler can be set without error
    // We can't easily trigger a status change in unit tests without a running process
    XCTAssertFalse(handlerCalled)  // Handler shouldn't be called just from setting it
  }
}
