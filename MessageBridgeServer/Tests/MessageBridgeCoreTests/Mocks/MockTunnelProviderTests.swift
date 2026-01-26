import XCTest

@testable import MessageBridgeCore

final class MockTunnelProviderTests: XCTestCase {

  func testConnectSuccess() async throws {
    let mock = MockTunnelProvider()
    await mock.setMockURL("https://test.example.com")

    let url = try await mock.connect(port: 8080)

    XCTAssertEqual(url, "https://test.example.com")
    let status = await mock.status
    XCTAssertTrue(status.isRunning)
  }

  func testConnectFailure() async {
    let mock = MockTunnelProvider()
    await mock.setShouldFailConnect(.timeout)

    do {
      _ = try await mock.connect(port: 8080)
      XCTFail("Expected error to be thrown")
    } catch let error as TunnelError {
      XCTAssertEqual(error, .timeout)
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testDisconnect() async throws {
    let mock = MockTunnelProvider()
    _ = try await mock.connect(port: 8080)

    var status = await mock.status
    XCTAssertTrue(status.isRunning)

    await mock.disconnect()

    status = await mock.status
    XCTAssertEqual(status, .stopped)
  }

  func testStatusChangeCallback() async throws {
    let mock = MockTunnelProvider()

    let expectation = XCTestExpectation(description: "Status change callback")
    var receivedStatuses: [TunnelStatus] = []

    await mock.onStatusChange { status in
      receivedStatuses.append(status)
      if case .running = status {
        expectation.fulfill()
      }
    }

    _ = try await mock.connect(port: 8080)

    await fulfillment(of: [expectation], timeout: 1.0)

    XCTAssertTrue(receivedStatuses.contains(.starting))
    XCTAssertTrue(receivedStatuses.contains { $0.isRunning })
  }

  func testProtocolConformance() async {
    let mock = MockTunnelProvider(
      id: "test-id",
      displayName: "Test Provider",
      description: "A test provider",
      iconName: "test.icon"
    )

    XCTAssertEqual(mock.id, "test-id")
    XCTAssertEqual(mock.displayName, "Test Provider")
    XCTAssertEqual(mock.description, "A test provider")
    XCTAssertEqual(mock.iconName, "test.icon")
    XCTAssertTrue(mock.isInstalled())

    let status = await mock.status
    XCTAssertEqual(status, .stopped)
  }

  func testIsInstalledFalse() async {
    let mock = MockTunnelProvider(isInstalled: false)

    XCTAssertFalse(mock.isInstalled())
  }

  func testSimulateStatus() async {
    let mock = MockTunnelProvider()

    let expectation = XCTestExpectation(description: "Simulate status")
    var receivedStatus: TunnelStatus?

    await mock.onStatusChange { status in
      receivedStatus = status
      expectation.fulfill()
    }

    await mock.simulateStatus(.error("Test error"))

    await fulfillment(of: [expectation], timeout: 1.0)

    XCTAssertEqual(receivedStatus, .error("Test error"))
    let status = await mock.status
    XCTAssertEqual(status, .error("Test error"))
  }

  func testConnectDelay() async throws {
    let mock = MockTunnelProvider()
    await mock.setConnectDelay(.milliseconds(100))

    let start = Date()
    _ = try await mock.connect(port: 8080)
    let elapsed = Date().timeIntervalSince(start)

    // Should take at least 100ms
    XCTAssertGreaterThan(elapsed, 0.09)
  }
}
