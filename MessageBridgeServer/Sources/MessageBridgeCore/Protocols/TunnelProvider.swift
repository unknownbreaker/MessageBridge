import Foundation

/// A tunnel provider that enables remote access to the MessageBridge server.
///
/// Implementations handle the details of different tunnel technologies:
/// - **Tailscale**: VPN mesh network (external app manages connection)
/// - **Cloudflare**: Quick tunnels via cloudflared process
/// - **ngrok**: Tunnels via ngrok process
///
/// ## Usage
///
/// ```swift
/// // Register providers at app startup
/// TunnelRegistry.shared.register(CloudflareProvider())
/// TunnelRegistry.shared.register(NgrokProvider())
/// TunnelRegistry.shared.register(TailscaleProvider())
///
/// // Connect via any provider
/// let provider = TunnelRegistry.shared.get("cloudflare")!
/// let url = try await provider.connect(port: 8080)
/// ```
public protocol TunnelProvider: Actor, Identifiable, Sendable {
  /// Unique identifier for this provider (e.g., "tailscale", "cloudflare", "ngrok")
  nonisolated var id: String { get }

  /// Human-readable name for UI display
  nonisolated var displayName: String { get }

  /// Short description of the tunnel type and its characteristics
  nonisolated var description: String { get }

  /// SF Symbol name for the provider icon in UI
  nonisolated var iconName: String { get }

  /// Current status of the tunnel
  var status: TunnelStatus { get async }

  /// Whether the underlying tunnel tool is installed on the system
  /// - Returns: `true` if the tool is available, `false` otherwise
  nonisolated func isInstalled() -> Bool

  /// Connect or activate the tunnel.
  ///
  /// The behavior varies by provider type:
  /// - **Process-based** (Cloudflare, ngrok): Starts the tunnel process
  /// - **External** (Tailscale): Verifies connection, may prompt user
  ///
  /// - Parameter port: The local port to expose through the tunnel
  /// - Returns: The public URL or IP address for accessing the tunnel
  /// - Throws: `TunnelError` if connection fails
  func connect(port: Int) async throws -> String

  /// Disconnect or deactivate the tunnel.
  ///
  /// For process-based tunnels, this terminates the process.
  /// For external tunnels (like Tailscale), this may be a no-op.
  func disconnect() async

  /// Register a callback to be notified of status changes.
  /// - Parameter handler: Closure called when status changes
  func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void)
}
