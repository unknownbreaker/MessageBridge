import AppKit

/// Deletes a message sent by the user. Currently shows a stub alert.
public struct DeleteAction: MessageAction {
  public let id = "delete"
  public let title = "Delete"
  public let icon = "trash"
  public let destructive = true
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    message.isFromMe
  }

  @MainActor
  public func perform(on message: Message) async {
    showStubAlert(title: title)
  }
}
