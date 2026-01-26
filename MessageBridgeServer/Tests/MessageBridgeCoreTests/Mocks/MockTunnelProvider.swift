import Foundation

@testable import MessageBridgeCore

/// Mock tunnel provider for testing
public actor MockTunnelProvider: TunnelProvider {
  public nonisolated let id: String
  public nonisolated let displayName: String
  public nonisolated let description: String
  public nonisolated let iconName: String
  private nonisolated let _isInstalled: Bool

  private var _status: TunnelStatus = .stopped
  private var statusHandler: ((TunnelStatus) -> Void)?

  /// Set this to make connect() throw an error
  public var shouldFailConnect: TunnelError?

  /// Set this to control the returned URL
  public var mockURL: String = "https://mock-tunnel.example.com"

  /// Delay before connect completes (for testing async behavior)
  public var connectDelay: Duration = .zero

  public init(
    id: String = "mock",
    displayName: String = "Mock Tunnel",
    description: String = "Mock tunnel for testing",
    iconName: String = "testtube.2",
    isInstalled: Bool = true
  ) {
    self.id = id
    self.displayName = displayName
    self.description = description
    self.iconName = iconName
    self._isInstalled = isInstalled
  }

  public var status: TunnelStatus {
    get async { _status }
  }

  public nonisolated func isInstalled() -> Bool {
    _isInstalled
  }

  public func connect(port: Int) async throws -> String {
    if let error = shouldFailConnect {
      throw error
    }

    updateStatus(.starting)

    if connectDelay > .zero {
      try await Task.sleep(for: connectDelay)
    }

    updateStatus(.running(url: mockURL, isQuickTunnel: true))
    return mockURL
  }

  public func disconnect() async {
    updateStatus(.stopped)
  }

  public func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void) {
    statusHandler = handler
  }

  // MARK: - Test Helpers

  public func simulateStatus(_ status: TunnelStatus) {
    updateStatus(status)
  }

  public func setShouldFailConnect(_ error: TunnelError?) {
    shouldFailConnect = error
  }

  public func setMockURL(_ url: String) {
    mockURL = url
  }

  public func setConnectDelay(_ delay: Duration) {
    connectDelay = delay
  }

  private func updateStatus(_ newStatus: TunnelStatus) {
    _status = newStatus
    statusHandler?(newStatus)
  }
}
