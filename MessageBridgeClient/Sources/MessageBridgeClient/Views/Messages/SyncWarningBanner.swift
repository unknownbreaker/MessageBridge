import SwiftUI

/// Banner displayed when read status sync fails for a conversation
struct SyncWarningBanner: View {
  let message: String
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
      Text(message)
        .foregroundStyle(.yellow)
        .font(.caption)
      Spacer()
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundStyle(.secondary)
          .font(.caption)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color.yellow.opacity(0.1))
  }
}

#Preview {
  VStack {
    SyncWarningBanner(
      message: "Read status could not be synced to Messages.app",
      onDismiss: {}
    )
    Spacer()
  }
}
