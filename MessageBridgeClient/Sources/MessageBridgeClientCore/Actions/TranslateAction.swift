import AppKit

/// Translates message text. Currently shows a stub alert.
public struct TranslateAction: MessageAction {
  public let id = "translate"
  public let title = "Translate"
  public let icon = "textformat"
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
