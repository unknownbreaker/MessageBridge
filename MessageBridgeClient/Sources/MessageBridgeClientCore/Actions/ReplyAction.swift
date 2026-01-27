import AppKit

/// Begins a reply to a message. Currently shows a stub alert.
public struct ReplyAction: MessageAction {
  public let id = "reply"
  public let title = "Reply"
  public let icon = "arrowshape.turn.up.left"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    true
  }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
