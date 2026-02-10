import SwiftUI

/// Protocol for actions available on messages (context menu, keyboard shortcuts).
///
/// Unlike renderers which select ONE best match, ALL available actions
/// are shown in the context menu.
public protocol MessageAction: Identifiable, Sendable {
  var id: String { get }
  var title: String { get }
  var icon: String { get }
  var destructive: Bool { get }

  func isAvailable(for message: Message) -> Bool
  @MainActor func perform(on message: Message) async
}
