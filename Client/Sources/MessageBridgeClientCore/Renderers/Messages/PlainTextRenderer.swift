import SwiftUI

/// Default fallback renderer for plain text messages.
///
/// Always returns `true` from `canRender` — this is the last-resort renderer
/// used when no higher-priority renderer matches the message.
public struct PlainTextRenderer: MessageRenderer {
  public let id = "plain-text"
  public let priority = 0

  public init() {}

  public func canRender(_ message: Message) -> Bool {
    true
  }

  @MainActor
  public func render(_ message: Message) -> AnyView {
    AnyView(
      Text(message.text ?? "")
    )
  }
}
