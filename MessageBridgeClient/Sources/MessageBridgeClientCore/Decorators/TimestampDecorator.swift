import SwiftUI

/// Decorator that shows the message timestamp below the bubble.
public struct TimestampDecorator: BubbleDecorator {
  public let id = "timestamp"
  public let position = DecoratorPosition.below
  public init() {}

  public func shouldDecorate(_ message: Message, context: DecoratorContext) -> Bool {
    true
  }

  @MainActor
  public func decorate(_ message: Message, context: DecoratorContext) -> AnyView {
    AnyView(
      Text(message.date, style: .time)
        .font(.caption2)
        .foregroundStyle(.secondary)
    )
  }
}
