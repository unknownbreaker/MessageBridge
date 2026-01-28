import XCTest

@testable import MessageBridgeCore

/// Blind spec-based audit tests for M2.2 Cloudflare Tunnel Support.
///
/// Written from spec.md acceptance criteria:
/// - Manages cloudflared process
/// - Setup wizard for first-time configuration
/// - Can set as default tunnel
final class CloudflareAuditTests: XCTestCase {

  // MARK: - Protocol Conformance

  func testConformsToTunnelProvider() {
    let manager = CloudflaredManager()
    XCTAssertTrue(manager is any TunnelProvider)
  }

  func testHasExpectedId() {
    let manager = CloudflaredManager()
    XCTAssertEqual(manager.id, "cloudflare")
  }

  func testHasDisplayName() {
    let manager = CloudflaredManager()
    XCTAssertFalse(manager.displayName.isEmpty)
  }

  func testHasDescription() {
    let manager = CloudflaredManager()
    XCTAssertFalse(manager.description.isEmpty)
  }

  func testHasIconName() {
    let manager = CloudflaredManager()
    XCTAssertFalse(manager.iconName.isEmpty)
  }

  // MARK: - TunnelStatus (shared type)

  func testTunnelStatus_coversExpectedStates() {
    let notInstalled = TunnelStatus.notInstalled
    let stopped = TunnelStatus.stopped
    let starting = TunnelStatus.starting
    let running = TunnelStatus.running(url: "https://test.trycloudflare.com", isQuickTunnel: true)
    let error = TunnelStatus.error("fail")

    XCTAssertNotEqual(notInstalled, stopped)
    XCTAssertNotEqual(stopped, starting)
    _ = running
    _ = error
  }

  func testTunnelStatus_isRunning() {
    XCTAssertFalse(TunnelStatus.notInstalled.isRunning)
    XCTAssertFalse(TunnelStatus.stopped.isRunning)
    XCTAssertFalse(TunnelStatus.starting.isRunning)
    XCTAssertTrue(
      TunnelStatus.running(url: "https://test.trycloudflare.com", isQuickTunnel: true).isRunning)
    XCTAssertFalse(TunnelStatus.error("fail").isRunning)
  }

  func testTunnelStatus_displayText_allStatesHaveText() {
    let states: [TunnelStatus] = [
      .notInstalled, .stopped, .starting,
      .running(url: "https://test.trycloudflare.com", isQuickTunnel: true),
      .running(url: "https://custom.example.com", isQuickTunnel: false),
      .error("test"),
    ]
    for state in states {
      XCTAssertFalse(state.displayText.isEmpty, "Status \(state) should have display text")
    }
  }

  func testTunnelStatus_url_extractsFromRunning() {
    let running = TunnelStatus.running(
      url: "https://test.trycloudflare.com", isQuickTunnel: true)
    XCTAssertEqual(running.url, "https://test.trycloudflare.com")

    XCTAssertNil(TunnelStatus.stopped.url)
    XCTAssertNil(TunnelStatus.starting.url)
  }

  func testTunnelStatus_quickVsNamed_differentDisplayText() {
    let quick = TunnelStatus.running(url: "https://a.trycloudflare.com", isQuickTunnel: true)
    let named = TunnelStatus.running(url: "https://custom.example.com", isQuickTunnel: false)
    // Quick and named tunnels should have distinguishable display text
    XCTAssertNotEqual(quick.displayText, named.displayText)
  }

  // MARK: - Initial State

  func testInitialStatus_isStopped() async {
    let manager = CloudflaredManager()
    let status = await manager.status
    XCTAssertEqual(status, .stopped)
  }

  // MARK: - CloudflaredInfo Model

  func testCloudflaredInfo_init() {
    let info = CloudflaredInfo(path: "/usr/local/bin/cloudflared", version: "2024.1.0")
    XCTAssertEqual(info.path, "/usr/local/bin/cloudflared")
    XCTAssertEqual(info.version, "2024.1.0")
  }

  func testCloudflaredInfo_nilVersion() {
    let info = CloudflaredInfo(path: "/usr/local/bin/cloudflared", version: nil)
    XCTAssertNil(info.version)
  }
}
