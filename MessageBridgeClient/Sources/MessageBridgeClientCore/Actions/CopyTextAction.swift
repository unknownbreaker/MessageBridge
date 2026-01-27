import AppKit

/// Copies message text to the clipboard.
public struct CopyTextAction: MessageAction {
  public let id = "copy-text"
  public let title = "Copy"
  public let icon = "doc.on.doc"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    message.hasText
  }

  @MainActor
  public func perform(on message: Message) async {
    guard let text = message.text else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
