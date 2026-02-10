import XCTest

@testable import MessageBridgeCore

/// Blind spec-based audit tests for M2.1 Tailscale Support.
///
/// Written from spec.md acceptance criteria:
/// - Auto-detect Tailscale IP address
/// - Status indicator in menu bar
/// - Can set as default tunnel
final class TailscaleAuditTests: XCTestCase {

  // MARK: - Protocol Conformance

  func testConformsToTunnelProvider() {
    let manager = TailscaleManager()
    XCTAssertTrue(manager is any TunnelProvider)
  }

  func testHasExpectedId() {
    let manager = TailscaleManager()
    XCTAssertEqual(manager.id, "tailscale")
  }

  func testHasDisplayName() {
    let manager = TailscaleManager()
    XCTAssertFalse(manager.displayName.isEmpty)
  }

  func testHasDescription() {
    let manager = TailscaleManager()
    XCTAssertFalse(manager.description.isEmpty)
  }

  func testHasIconName() {
    let manager = TailscaleManager()
    XCTAssertFalse(manager.iconName.isEmpty)
  }

  // MARK: - Status Types (M2.1: "Status indicator")

  func testTailscaleStatus_coversExpectedStates() {
    let notInstalled = TailscaleStatus.notInstalled
    let stopped = TailscaleStatus.stopped
    let connecting = TailscaleStatus.connecting
    let connected = TailscaleStatus.connected(ip: "100.64.0.1", hostname: "mac")
    let error = TailscaleStatus.error("fail")

    // All states should be distinguishable
    XCTAssertNotEqual(notInstalled, stopped)
    XCTAssertNotEqual(stopped, connecting)
    XCTAssertNotEqual(connecting, notInstalled)
    _ = connected
    _ = error
  }

  func testTailscaleStatus_isConnected() {
    XCTAssertFalse(TailscaleStatus.notInstalled.isConnected)
    XCTAssertFalse(TailscaleStatus.stopped.isConnected)
    XCTAssertFalse(TailscaleStatus.connecting.isConnected)
    XCTAssertTrue(TailscaleStatus.connected(ip: "100.64.0.1", hostname: "mac").isConnected)
    XCTAssertFalse(TailscaleStatus.error("fail").isConnected)
  }

  func testTailscaleStatus_displayText_allStatesHaveText() {
    let states: [TailscaleStatus] = [
      .notInstalled, .stopped, .connecting,
      .connected(ip: "100.64.0.1", hostname: "mac"),
      .error("test"),
    ]
    for state in states {
      XCTAssertFalse(state.displayText.isEmpty, "Status \(state) should have display text")
    }
  }

  func testTailscaleStatus_ipAddress_extractsFromConnected() {
    let connected = TailscaleStatus.connected(ip: "100.64.0.1", hostname: "mac")
    XCTAssertEqual(connected.ipAddress, "100.64.0.1")

    let stopped = TailscaleStatus.stopped
    XCTAssertNil(stopped.ipAddress)
  }

  // MARK: - Device Model (M2.1: "Auto-detect Tailscale IP address")

  func testTailscaleDevice_hasExpectedProperties() {
    let device = TailscaleDevice(
      id: "node1", name: "my-mac", ipAddresses: ["100.64.0.1", "fd7a::1"],
      online: true, os: "macOS", isSelf: true)
    XCTAssertEqual(device.id, "node1")
    XCTAssertEqual(device.name, "my-mac")
    XCTAssertEqual(device.ipAddresses, ["100.64.0.1", "fd7a::1"])
    XCTAssertTrue(device.online)
    XCTAssertTrue(device.isSelf)
  }

  func testTailscaleDevice_displayIP_returnsFirst() {
    let device = TailscaleDevice(
      id: "n", name: "n", ipAddresses: ["100.64.0.1", "fd7a::1"],
      online: true, os: nil, isSelf: false)
    XCTAssertEqual(device.displayIP, "100.64.0.1")
  }

  func testTailscaleDevice_displayIP_emptyAddresses() {
    let device = TailscaleDevice(
      id: "n", name: "n", ipAddresses: [],
      online: false, os: nil, isSelf: false)
    XCTAssertEqual(device.displayIP, "Unknown")
  }

  // MARK: - TunnelProvider Status Bridge

  func testStatus_returnsTunnelStatus() async {
    let manager = TailscaleManager()
    let status = await manager.status
    // Should not crash — just verify the property exists and returns
    _ = status
  }
}
