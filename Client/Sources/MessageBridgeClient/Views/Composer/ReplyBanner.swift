import MessageBridgeClientCore
import SwiftUI

/// Banner shown above the composer when replying to a message.
struct ReplyBanner: View {
  let message: Message
  let onCancel: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 1)
        .fill(Color.accentColor)
        .frame(width: 2)

      VStack(alignment: .leading, spacing: 1) {
        Text(message.isFromMe ? "You" : "Reply")
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundStyle(Color.accentColor)

        if let text = message.text {
          Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      Button {
        onCancel()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
          .font(.body)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)
  }
}
