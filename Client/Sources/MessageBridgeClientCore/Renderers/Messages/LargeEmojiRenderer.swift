import SwiftUI

/// Renderer for messages containing only 1-3 emoji characters.
///
/// Displays emoji at a larger font size without needing a bubble background,
/// matching the Apple Messages behavior for emoji-only messages.
public struct LargeEmojiRenderer: MessageRenderer {
  public let id = "large-emoji"
  public let priority = 50

  public init() {}

  public func canRender(_ message: Message) -> Bool {
    guard let text = message.text, !text.isEmpty else { return false }
    let isAllEmoji = text.allSatisfy { $0.isEmoji }
    return isAllEmoji && text.count >= 1 && text.count <= 3
  }

  @MainActor
  public func render(_ message: Message) -> AnyView {
    AnyView(
      Text(message.text ?? "")
        .font(.system(size: 48))
    )
  }
}

extension Character {
  /// Whether this character is an emoji.
  ///
  /// Checks if the first unicode scalar has emoji presentation or
  /// is a non-ASCII emoji scalar. This avoids treating ASCII characters
  /// like # or digits as emoji.
  fileprivate var isEmoji: Bool {
    guard let scalar = unicodeScalars.first else { return false }
    return scalar.properties.isEmojiPresentation
      || (scalar.properties.isEmoji && scalar.value > 0x7F)
  }
}
