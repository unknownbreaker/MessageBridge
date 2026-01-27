import AppKit

/// Forwards a message to another conversation. Currently shows a stub alert.
public struct ForwardAction: MessageAction {
  public let id = "forward"
  public let title = "Forward"
  public let icon = "arrowshape.turn.up.right"
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
