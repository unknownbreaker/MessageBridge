import SwiftUI

/// Context passed to decorators for decision-making.
public struct DecoratorContext: Sendable {
  /// Whether this message is the last one sent by the current user in the conversation
  public let isLastSentMessage: Bool
  /// Whether this message is the very last message in the conversation
  public let isLastMessage: Bool
  /// The conversation this message belongs to
  public let conversationId: String

  public init(isLastSentMessage: Bool, isLastMessage: Bool, conversationId: String) {
    self.isLastSentMessage = isLastSentMessage
    self.isLastMessage = isLastMessage
    self.conversationId = conversationId
  }
}

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
  func shouldDecorate(_ message: Message, context: DecoratorContext) -> Bool
  @MainActor func decorate(_ message: Message, context: DecoratorContext) -> AnyView
}
