import SwiftUI

/// Position of a decorator relative to the message bubble.
public enum DecoratorPosition: String, Codable, Sendable {
  case topLeading
  case topTrailing
  case bottomLeading
  case bottomTrailing
  case below
  case overlay
}

/// Protocol for adding decorations around message bubbles.
///
/// Unlike renderers which select ONE best match, multiple decorators
/// can coexist at different positions around the bubble.
public protocol BubbleDecorator: Identifiable, Sendable {
  var id: String { get }
  var position: DecoratorPosition { get }
  func shouldDecorate(_ message: Message) -> Bool
  @MainActor func decorate(_ message: Message) -> AnyView
}
