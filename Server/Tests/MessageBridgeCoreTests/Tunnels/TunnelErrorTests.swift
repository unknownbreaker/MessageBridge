import XCTest

@testable import MessageBridgeCore

final class TunnelErrorTests: XCTestCase {

  func testNotInstalledDescription() {
    let error = TunnelError.notInstalled(provider: "cloudflare")
    XCTAssertEqual(error.errorDescription, "cloudflare is not installed")
  }

  func testConnectionFailedDescription() {
    let error = TunnelError.connectionFailed("network unreachable")
    XCTAssertEqual(error.errorDescription, "Connection failed: network unreachable")
  }

  func testTimeoutDescription() {
    let error = TunnelError.timeout
    XCTAssertEqual(error.errorDescription, "Timed out waiting for tunnel connection")
  }

  func testUserActionRequiredDescription() {
    let error = TunnelError.userActionRequired("Please connect in Tailscale app")
    XCTAssertEqual(error.errorDescription, "Please connect in Tailscale app")
  }

  func testInstallationFailedDescription() {
    let error = TunnelError.installationFailed(reason: "disk full")
    XCTAssertEqual(error.errorDescription, "Installation failed: disk full")
  }

  func testUnexpectedTerminationDescription() {
    let error = TunnelError.unexpectedTermination(exitCode: 1)
    XCTAssertEqual(error.errorDescription, "Tunnel terminated unexpectedly (exit code 1)")
  }

  func testAuthenticationFailedDescription() {
    let error = TunnelError.authenticationFailed("invalid token")
    XCTAssertEqual(error.errorDescription, "Authentication failed: invalid token")
  }

  func testErrorEquality() {
    XCTAssertEqual(TunnelError.timeout, TunnelError.timeout)
    XCTAssertEqual(
      TunnelError.notInstalled(provider: "ngrok"),
      TunnelError.notInstalled(provider: "ngrok")
    )
    XCTAssertNotEqual(
      TunnelError.notInstalled(provider: "ngrok"),
      TunnelError.notInstalled(provider: "cloudflare")
    )
  }
}
