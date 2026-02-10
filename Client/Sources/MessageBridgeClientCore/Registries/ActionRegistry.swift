import Foundation

/// Singleton registry for message actions.
///
/// Returns ALL available actions for a message in registration order.
public final class ActionRegistry: @unchecked Sendable {
  public static let shared = ActionRegistry()
  private var actions: [any MessageAction] = []
  private let lock = NSLock()
  private init() {}

  public func register(_ action: any MessageAction) {
    lock.lock()
    defer { lock.unlock() }
    actions.append(action)
  }

  public func availableActions(for message: Message) -> [any MessageAction] {
    lock.lock()
    defer { lock.unlock() }
    return actions.filter { $0.isAvailable(for: message) }
  }

  public var all: [any MessageAction] {
    lock.lock()
    defer { lock.unlock() }
    return actions
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    actions.removeAll()
  }
}
