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
        let status = TunnelStatus.running(url: "https://messagebridge.example.com", isQuickTunnel: false)
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
}
