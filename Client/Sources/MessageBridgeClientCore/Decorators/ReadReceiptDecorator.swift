import SwiftUI

/// Decorator that shows delivery status below the last sent message.
///
/// Displays "Sent", "Delivered", or "Read" at the bottom-trailing position.
/// Tap toggles visibility of the timestamp.
public struct ReadReceiptDecorator: BubbleDecorator {
  public let id = "read-receipt"
  public let position = DecoratorPosition.bottomTrailing

  public init() {}

  public func shouldDecorate(_ message: Message, context: DecoratorContext) -> Bool {
    guard message.isFromMe, context.isLastSentMessage else { return false }
    return message.deliveryStatus != .none
  }

  @MainActor
  public func decorate(_ message: Message, context: DecoratorContext) -> AnyView {
    AnyView(
      ReadReceiptView(
        status: message.deliveryStatus,
        dateRead: message.dateRead,
        dateDelivered: message.dateDelivered
      )
    )
  }
}

struct ReadReceiptView: View {
  let status: DeliveryStatus
  let dateRead: Date?
  let dateDelivered: Date?
  @State private var showTimestamp = false

  var body: some View {
    Text(displayText)
      .font(.caption2)
      .foregroundStyle(.secondary)
      .onTapGesture { showTimestamp.toggle() }
  }

  private var displayText: String {
    switch status {
    case .read:
      return showTimestamp ? "Read \(formatted(dateRead))" : "Read"
    case .delivered:
      return showTimestamp ? "Delivered \(formatted(dateDelivered))" : "Delivered"
    case .sent:
      return "Sent"
    case .none:
      return ""
    }
  }

  private func formatted(_ date: Date?) -> String {
    guard let date else { return "" }
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
  }
}
