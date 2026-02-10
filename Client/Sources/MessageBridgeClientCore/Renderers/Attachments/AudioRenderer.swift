import SwiftUI

/// Renderer for audio attachments.
///
/// Shows a compact player-style row with waveform icon, filename, and size.
public struct AudioRenderer: AttachmentRenderer {
  public let id = "audio"
  public let priority = 50

  public init() {}

  public func canRender(_ attachments: [Attachment]) -> Bool {
    !attachments.isEmpty && attachments.allSatisfy { $0.isAudio }
  }

  @MainActor
  public func render(_ attachments: [Attachment]) -> AnyView {
    AnyView(
      VStack(spacing: 4) {
        ForEach(attachments) { attachment in
          AudioAttachmentRow(attachment: attachment)
        }
      }
    )
  }
}

struct AudioAttachmentRow: View {
  let attachment: Attachment

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "waveform")
        .font(.title2)
        .foregroundStyle(.blue)
        .frame(width: 40, height: 40)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 2) {
        Text(attachment.filename)
          .font(.caption)
          .lineLimit(1)
        Text(attachment.formattedSize)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "play.circle.fill")
        .font(.title2)
        .foregroundStyle(.blue)
    }
    .padding(12)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .frame(maxWidth: 250)
  }
}
