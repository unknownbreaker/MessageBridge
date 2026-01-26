import Foundation

/// Central registry for all tunnel providers.
///
/// The registry is a singleton that holds references to all available tunnel providers.
/// Providers register themselves at app startup, and UI components query the registry
/// to discover and interact with providers.
///
/// ## Usage
///
/// ```swift
/// // At app startup
/// TunnelRegistry.shared.register(CloudflareProvider())
/// TunnelRegistry.shared.register(NgrokProvider())
///
/// // Query providers
/// let allProviders = TunnelRegistry.shared.all
/// let cloudflare = TunnelRegistry.shared.get("cloudflare")
/// ```
///
/// ## Thread Safety
///
/// All methods are thread-safe and can be called from any thread.
public final class TunnelRegistry: @unchecked Sendable {
  /// Shared singleton instance
  public static let shared = TunnelRegistry()

  private var providers: [String: any TunnelProvider] = [:]
  private let lock = NSLock()

  private init() {}

  /// Register a tunnel provider.
  ///
  /// If a provider with the same ID is already registered, it will be replaced.
  ///
  /// - Parameter provider: The provider to register
  public func register(_ provider: any TunnelProvider) {
    lock.lock()
    defer { lock.unlock() }
    providers[provider.id] = provider
  }

  /// Get a provider by its ID.
  ///
  /// - Parameter id: The provider's unique identifier
  /// - Returns: The provider if found, `nil` otherwise
  public func get(_ id: String) -> (any TunnelProvider)? {
    lock.lock()
    defer { lock.unlock() }
    return providers[id]
  }

  /// All registered providers.
  ///
  /// The order of providers is not guaranteed.
  public var all: [any TunnelProvider] {
    lock.lock()
    defer { lock.unlock() }
    return Array(providers.values)
  }

  /// The number of registered providers.
  public var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return providers.count
  }

  /// Check if a provider with the given ID is registered.
  ///
  /// - Parameter id: The provider's unique identifier
  /// - Returns: `true` if registered, `false` otherwise
  public func contains(_ id: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return providers[id] != nil
  }

  /// Remove a provider by its ID.
  ///
  /// - Parameter id: The provider's unique identifier
  /// - Returns: The removed provider if found, `nil` otherwise
  @discardableResult
  public func remove(_ id: String) -> (any TunnelProvider)? {
    lock.lock()
    defer { lock.unlock() }
    return providers.removeValue(forKey: id)
  }

  /// Remove all registered providers.
  ///
  /// Primarily useful for testing.
  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    providers.removeAll()
  }
}
