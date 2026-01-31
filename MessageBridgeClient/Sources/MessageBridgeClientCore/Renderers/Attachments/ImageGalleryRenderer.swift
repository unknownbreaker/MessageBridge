import SwiftUI

/// Renderer for messages with 2+ image attachments.
///
/// Displays images in a horizontally-scrollable strip inside the bubble.
/// Tapping any image opens the fullscreen carousel at that index.
/// Non-image attachments in the group are rendered below the strip
/// via the registry.
public struct ImageGalleryRenderer: AttachmentRenderer {
  public let id = "image-gallery"
  public let priority = 100

  public init() {}

  public func canRender(_ attachments: [Attachment]) -> Bool {
    attachments.filter(\.isImage).count >= 2
  }

  @MainActor
  public func render(_ attachments: [Attachment]) -> AnyView {
    let images = attachments.filter(\.isImage)
    let nonImages = attachments.filter { !$0.isImage }

    return AnyView(
      VStack(spacing: 4) {
        ImageStripView(attachments: images)

        if !nonImages.isEmpty {
          ForEach(nonImages) { attachment in
            AttachmentRendererRegistry.shared
              .renderer(for: [attachment])
              .render([attachment])
          }
        }
      }
    )
  }
}

struct ImageStripView: View {
  let attachments: [Attachment]

  @State private var isShowingCarousel = false
  @State private var carouselStartIndex = 0

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 2) {
        ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
          Group {
            if let data = attachment.thumbnailData, let nsImage = NSImage(data: data) {
              Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 375)
                .frame(maxWidth: 330)
                .clipped()
            } else {
              Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 140, height: 375)
                .overlay {
                  Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                }
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .onTapGesture {
            carouselStartIndex = index
            isShowingCarousel = true
          }
        }
      }
    }
    .frame(maxWidth: 420, maxHeight: 375)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .sheet(isPresented: $isShowingCarousel) {
      CarouselView(attachments: attachments, startIndex: carouselStartIndex)
    }
  }
}
