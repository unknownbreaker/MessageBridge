import Foundation

/// Singleton registry for composer plugins.
///
/// Returns all registered plugins in registration order.
public final class ComposerRegistry: @unchecked Sendable {
  public static let shared = ComposerRegistry()
  private var plugins: [any ComposerPlugin] = []
  private let lock = NSLock()
  private init() {}

  public func register(_ plugin: any ComposerPlugin) {
    lock.lock()
    defer { lock.unlock() }
    plugins.append(plugin)
  }

  public func unregister(_ id: String) {
    lock.lock()
    defer { lock.unlock() }
    plugins.removeAll { $0.id == id }
  }

  public var all: [any ComposerPlugin] {
    lock.lock()
    defer { lock.unlock() }
    return plugins
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    plugins.removeAll()
  }
}
