import Foundation

/// Singleton registry for message content renderers.
///
/// Renderers are selected by priority — highest priority renderer whose
/// `canRender` returns true is used. Falls back to PlainTextRenderer
/// when no registered renderer matches.
public final class RendererRegistry: @unchecked Sendable {
  public static let shared = RendererRegistry()

  private var renderers: [any MessageRenderer] = []
  private let lock = NSLock()

  private init() {}

  /// Register a renderer.
  public func register(_ renderer: any MessageRenderer) {
    lock.lock()
    defer { lock.unlock() }
    renderers.append(renderer)
  }

  /// Find the best renderer for a message.
  public func renderer(for message: Message) -> any MessageRenderer {
    lock.lock()
    defer { lock.unlock() }
    return
      renderers
      .sorted { $0.priority > $1.priority }
      .first { $0.canRender(message) }
      ?? PlainTextRenderer()
  }

  /// All registered renderers.
  public var all: [any MessageRenderer] {
    lock.lock()
    defer { lock.unlock() }
    return renderers
  }

  /// Reset for testing.
  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    renderers.removeAll()
  }
}
