import XCTest

@testable import MessageBridgeCore

final class TunnelProviderIntegrationTests: XCTestCase {

  override func setUp() {
    super.setUp()
    TunnelRegistry.shared.reset()
  }

  override func tearDown() {
    TunnelRegistry.shared.reset()
    super.tearDown()
  }

  func testMultipleProvidersInRegistry() async throws {
    // Register multiple mock providers
    let cloudflare = MockTunnelProvider(id: "cloudflare", displayName: "Cloudflare")
    let ngrok = MockTunnelProvider(id: "ngrok", displayName: "ngrok")
    let tailscale = MockTunnelProvider(id: "tailscale", displayName: "Tailscale")

    TunnelRegistry.shared.register(cloudflare)
    TunnelRegistry.shared.register(ngrok)
    TunnelRegistry.shared.register(tailscale)

    // Verify all are registered
    XCTAssertEqual(TunnelRegistry.shared.count, 3)

    // Connect via one provider
    let cf = TunnelRegistry.shared.get("cloudflare")!
    let url = try await cf.connect(port: 8080)
    XCTAssertFalse(url.isEmpty)

    // Verify status
    let status = await cf.status
    XCTAssertTrue(status.isRunning)

    // Other providers should still be stopped
    let ngrokStatus = await TunnelRegistry.shared.get("ngrok")!.status
    XCTAssertEqual(ngrokStatus, .stopped)
  }

  func testConnectDisconnectCycle() async throws {
    let mock = MockTunnelProvider(id: "test")
    await mock.setMockURL("https://tunnel.example.com")
    TunnelRegistry.shared.register(mock)

    let provider = TunnelRegistry.shared.get("test")!

    // Initial state
    var status = await provider.status
    XCTAssertEqual(status, .stopped)

    // Connect
    let url = try await provider.connect(port: 8080)
    XCTAssertEqual(url, "https://tunnel.example.com")

    status = await provider.status
    XCTAssertTrue(status.isRunning)
    XCTAssertEqual(status.url, "https://tunnel.example.com")

    // Disconnect
    await provider.disconnect()

    status = await provider.status
    XCTAssertEqual(status, .stopped)
  }

  func testProviderErrorHandling() async {
    let mock = MockTunnelProvider(id: "failing")
    await mock.setShouldFailConnect(.notInstalled(provider: "failing"))
    TunnelRegistry.shared.register(mock)

    let provider = TunnelRegistry.shared.get("failing")!

    do {
      _ = try await provider.connect(port: 8080)
      XCTFail("Expected error")
    } catch let error as TunnelError {
      XCTAssertEqual(error, .notInstalled(provider: "failing"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAllProvidersHaveUniqueIds() async {
    let cloudflare = MockTunnelProvider(id: "cloudflare")
    let ngrok = MockTunnelProvider(id: "ngrok")
    let tailscale = MockTunnelProvider(id: "tailscale")

    TunnelRegistry.shared.register(cloudflare)
    TunnelRegistry.shared.register(ngrok)
    TunnelRegistry.shared.register(tailscale)

    let ids = Set(TunnelRegistry.shared.all.map { $0.id })
    XCTAssertEqual(ids.count, 3)
    XCTAssertTrue(ids.contains("cloudflare"))
    XCTAssertTrue(ids.contains("ngrok"))
    XCTAssertTrue(ids.contains("tailscale"))
  }

  func testProviderReplacementOnDuplicateId() async throws {
    let original = MockTunnelProvider(id: "test", displayName: "Original")
    await original.setMockURL("https://original.example.com")

    let replacement = MockTunnelProvider(id: "test", displayName: "Replacement")
    await replacement.setMockURL("https://replacement.example.com")

    TunnelRegistry.shared.register(original)
    TunnelRegistry.shared.register(replacement)

    // Should only have one provider
    XCTAssertEqual(TunnelRegistry.shared.count, 1)

    // Should be the replacement
    let provider = TunnelRegistry.shared.get("test")!
    XCTAssertEqual(provider.displayName, "Replacement")

    let url = try await provider.connect(port: 8080)
    XCTAssertEqual(url, "https://replacement.example.com")
  }

  func testConcurrentRegistration() async {
    // Register providers concurrently to test thread safety
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          let provider = MockTunnelProvider(id: "provider-\(i)")
          TunnelRegistry.shared.register(provider)
        }
      }
    }

    XCTAssertEqual(TunnelRegistry.shared.count, 10)
  }

  func testStatusTransitionsDuringConnect() async throws {
    let mock = MockTunnelProvider(id: "status-test")
    await mock.setMockURL("https://status.example.com")
    TunnelRegistry.shared.register(mock)

    let provider = TunnelRegistry.shared.get("status-test")!

    // Initial state should be stopped
    var status = await provider.status
    XCTAssertEqual(status, .stopped)

    // Connect and verify final state is running
    let url = try await provider.connect(port: 8080)
    XCTAssertEqual(url, "https://status.example.com")

    status = await provider.status
    XCTAssertTrue(status.isRunning)
    XCTAssertEqual(status.url, "https://status.example.com")

    // Disconnect and verify state returns to stopped
    await provider.disconnect()
    status = await provider.status
    XCTAssertEqual(status, .stopped)
  }

  func testProviderInstallationCheck() async {
    let installed = MockTunnelProvider(id: "installed", isInstalled: true)
    let notInstalled = MockTunnelProvider(id: "not-installed", isInstalled: false)

    TunnelRegistry.shared.register(installed)
    TunnelRegistry.shared.register(notInstalled)

    XCTAssertTrue(TunnelRegistry.shared.get("installed")!.isInstalled())
    XCTAssertFalse(TunnelRegistry.shared.get("not-installed")!.isInstalled())
  }
}
