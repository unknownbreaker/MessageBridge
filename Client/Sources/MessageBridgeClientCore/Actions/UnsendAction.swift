import AppKit

/// Unsends a recently sent message. Currently shows a stub alert.
public struct UnsendAction: MessageAction {
  public let id = "unsend"
  public let title = "Unsend"
  public let icon = "arrow.uturn.backward"
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
