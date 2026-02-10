import AppKit

/// Shows the tapback picker for a message.
/// Posts .showTapbackPicker notification with the message in userInfo.
public struct TapbackAction: MessageAction {
  public let id = "tapback"
  public let title = "Tapback"
  public let icon = "face.smiling"
  public let destructive = false
  public init() {}

  public func isAvailable(for message: Message) -> Bool {
    true
  }

  @MainActor
  public func perform(on message: Message) async {
    NotificationCenter.default.post(
      name: .showTapbackPicker,
      object: nil,
      userInfo: ["message": message]
    )
  }
}
