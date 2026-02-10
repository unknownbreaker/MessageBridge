import SwiftUI

/// Decorator that shows a reply quote bar above the message bubble
/// when the message is a reply to another message.
public struct ReplyPreviewDecorator: BubbleDecorator {
  public let id = "replyPreview"
  public let position = DecoratorPosition.topLeading

  public init() {}

  public func shouldDecorate(_ message: Message, context: DecoratorContext) -> Bool {
    message.replyToGuid != nil || message.threadOriginatorGuid != nil
  }

  @MainActor
  public func decorate(_ message: Message, context: DecoratorContext) -> AnyView {
    AnyView(
      ReplyQuoteBar(message: message)
        .padding(.bottom, 2)
    )
  }
}

/// Compact quote bar showing the original message context for replies.
/// Displays a colored left border with "Reply" label.
public struct ReplyQuoteBar: View {
  let message: Message

  public init(message: Message) {
    self.message = message
  }

  public var body: some View {
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 1)
        .fill(message.isFromMe ? Color.gray : Color.accentColor)
        .frame(width: 2)

      VStack(alignment: .leading, spacing: 1) {
        Text("Reply")
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .frame(maxWidth: 200, alignment: .leading)
  }
}
