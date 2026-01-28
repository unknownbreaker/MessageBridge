import SwiftUI

/// Decorator that shows tapback reactions above the message bubble.
///
/// Displays a pill-shaped view containing emoji reactions (love, like, dislike,
/// laugh, emphasis, question) at the top-trailing position of the message bubble.
public struct TapbackDecorator: BubbleDecorator {
  public let id = "tapback"
  public let position = DecoratorPosition.topTrailing

  public init() {}

  public func shouldDecorate(_ message: Message) -> Bool {
    guard let tapbacks = message.tapbacks else { return false }
    return !tapbacks.isEmpty
  }

  @MainActor
  public func decorate(_ message: Message) -> AnyView {
    AnyView(
      TapbackPill(tapbacks: message.tapbacks ?? [])
        .offset(x: 8, y: -8)
    )
  }
}
