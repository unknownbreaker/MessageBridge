import SwiftUI

/// Renderer for a single image attachment.
///
/// Shows thumbnail with tap-to-enlarge support.
public struct SingleImageRenderer: AttachmentRenderer {
  public let id = "single-image"
  public let priority = 50

  public init() {}

  public func canRender(_ attachments: [Attachment]) -> Bool {
    attachments.count == 1 && attachments[0].isImage
  }

  @MainActor
  public func render(_ attachments: [Attachment]) -> AnyView {
    AnyView(
      SingleImageView(attachment: attachments[0])
    )
  }
}

struct SingleImageView: View {
  let attachment: Attachment
  @State private var isShowingCarousel = false

  var body: some View {
    Group {
      if let thumbnailData = attachment.thumbnailData,
        let nsImage = NSImage(data: thumbnailData)
      {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: 375, maxHeight: 375)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .onTapGesture { isShowingCarousel = true }
      } else {
        HStack(spacing: 8) {
          Image(systemName: "photo")
            .foregroundStyle(.secondary)
          Text(attachment.filename)
            .font(.caption)
            .lineLimit(1)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
    }
    .sheet(isPresented: $isShowingCarousel) {
      CarouselView(attachments: [attachment], startIndex: 0)
    }
  }
}
