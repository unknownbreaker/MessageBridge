import Foundation

/// Singleton registry for attachment renderers.
///
/// Selects the highest-priority renderer whose `canRender` returns true.
/// Falls back to DocumentRenderer when no match is found.
public final class AttachmentRendererRegistry: @unchecked Sendable {
  public static let shared = AttachmentRendererRegistry()

  private var renderers: [any AttachmentRenderer] = []
  private let lock = NSLock()

  private init() {}

  public func register(_ renderer: any AttachmentRenderer) {
    lock.lock()
    defer { lock.unlock() }
    renderers.append(renderer)
  }

  public func renderer(for attachments: [Attachment]) -> any AttachmentRenderer {
    lock.lock()
    defer { lock.unlock() }
    return
      renderers
      .sorted { $0.priority > $1.priority }
      .first { $0.canRender(attachments) }
      ?? DocumentRenderer()
  }

  public var all: [any AttachmentRenderer] {
    lock.lock()
    defer { lock.unlock() }
    return renderers
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    renderers.removeAll()
  }
}
