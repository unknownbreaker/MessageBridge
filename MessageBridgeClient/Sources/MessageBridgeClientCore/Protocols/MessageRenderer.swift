import SwiftUI

/// Protocol for rendering message text content.
///
/// Implementations handle different content types (plain text, link previews,
/// large emoji, code highlights). The RendererRegistry selects the highest-priority
/// renderer whose `canRender` returns true for a given message.
///
/// Renderers only handle the text/content area of a message bubble.
/// Bubble chrome (avatar, timestamp, background) is managed by MessageBubble.
public protocol MessageRenderer: Identifiable, Sendable {
  /// Unique identifier for this renderer
  var id: String { get }

  /// Priority for renderer selection. Higher priority renderers are checked first.
  var priority: Int { get }

  /// Whether this renderer can handle the given message.
  func canRender(_ message: Message) -> Bool

  /// Render the message content.
  @MainActor func render(_ message: Message) -> AnyView
}
