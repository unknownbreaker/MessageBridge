import AppKit

/// Copies the first detected verification code to the clipboard.
public struct CopyCodeAction: MessageAction {
  public let id = "copy-code"
  public let title = "Copy Code"
  public let icon = "number.square"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    guard let codes = message.detectedCodes else { return false }
    return !codes.isEmpty
  }

  @MainActor
  public func perform(on message: Message) async {
    guard let code = message.detectedCodes?.first else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code.value, forType: .string)
  }
}
