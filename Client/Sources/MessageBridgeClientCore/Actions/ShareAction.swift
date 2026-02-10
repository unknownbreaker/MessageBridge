import AppKit

/// Shares a message via the system share sheet. Currently shows a stub alert.
public struct ShareAction: MessageAction {
  public let id = "share"
  public let title = "Share"
  public let icon = "square.and.arrow.up"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    message.hasText
  }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
