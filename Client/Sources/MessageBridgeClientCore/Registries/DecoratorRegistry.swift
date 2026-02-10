import Foundation

/// Singleton registry for bubble decorators.
///
/// Returns ALL matching decorators for a position, not just one.
public final class DecoratorRegistry: @unchecked Sendable {
  public static let shared = DecoratorRegistry()
  private var decorators: [any BubbleDecorator] = []
  private let lock = NSLock()
  private init() {}

  public func register(_ decorator: any BubbleDecorator) {
    lock.lock()
    defer { lock.unlock() }
    decorators.append(decorator)
  }

  public func decorators(
    for message: Message, at position: DecoratorPosition, context: DecoratorContext
  )
    -> [any BubbleDecorator]
  {
    lock.lock()
    defer { lock.unlock() }
    return decorators.filter {
      $0.position == position && $0.shouldDecorate(message, context: context)
    }
  }

  public var all: [any BubbleDecorator] {
    lock.lock()
    defer { lock.unlock() }
    return decorators
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    decorators.removeAll()
  }
}
