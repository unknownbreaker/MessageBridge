import AppKit
import Foundation

extension Notification.Name {
  public static let beginReply = Notification.Name("messageAction.beginReply")
  public static let showTapbackPicker = Notification.Name("messageAction.showTapbackPicker")
  public static let forwardMessage = Notification.Name("messageAction.forwardMessage")
  public static let deleteMessage = Notification.Name("messageAction.deleteMessage")
  public static let unsendMessage = Notification.Name("messageAction.unsendMessage")
  public static let shareMessage = Notification.Name("messageAction.shareMessage")
  public static let translateMessage = Notification.Name("messageAction.translateMessage")
}

/// Shows a "not yet implemented" alert for stub actions.
@MainActor
func showStubAlert(title: String) {
  let alert = NSAlert()
  alert.messageText = "Not Yet Implemented"
  alert.informativeText = "\(title) will be available in a future update."
  alert.alertStyle = .informational
  alert.addButton(withTitle: "OK")
  alert.runModal()
}
