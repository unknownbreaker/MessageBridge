import SwiftUI

/// Renderer for video attachments.
///
/// Shows thumbnail with play button overlay, or a placeholder if no thumbnail.
public struct VideoRenderer: AttachmentRenderer {
  public let id = "video"
  public let priority = 50

  public init() {}

  public func canRender(_ attachments: [Attachment]) -> Bool {
    !attachments.isEmpty && attachments.allSatisfy { $0.isVideo }
  }

  @MainActor
  public func render(_ attachments: [Attachment]) -> AnyView {
    AnyView(
      VStack(spacing: 4) {
        ForEach(attachments) { attachment in
          VideoThumbnailView(attachment: attachment)
        }
      }
    )
  }
}

struct VideoThumbnailView: View {
  let attachment: Attachment

  var body: some View {
    ZStack {
      if let thumbnailData = attachment.thumbnailData,
        let nsImage = NSImage(data: thumbnailData)
      {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: 250, maxHeight: 200)
      } else {
        Rectangle()
          .fill(Color(nsColor: .controlBackgroundColor))
          .frame(width: 200, height: 150)
          .overlay {
            Image(systemName: "video.fill")
              .font(.title)
              .foregroundStyle(.secondary)
          }
      }

      Circle()
        .fill(.black.opacity(0.6))
        .frame(width: 44, height: 44)
        .overlay {
          Image(systemName: "play.fill")
            .foregroundStyle(.white)
            .font(.title3)
        }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(alignment: .bottomTrailing) {
      Text(attachment.formattedSize)
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(6)
    }
  }
}
