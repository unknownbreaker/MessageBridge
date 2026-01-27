import SwiftUI

/// Renderer for messages with 2+ image attachments.
///
/// Displays images in a grid layout (2 columns). Shows up to 4 images,
/// with a "+N" overlay on the last cell if there are more.
/// Non-image attachments in the group are rendered below the grid
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
        ImageGridView(attachments: images)

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

struct ImageGridView: View {
  let attachments: [Attachment]
  private let maxDisplay = 4

  var body: some View {
    let displayAttachments = Array(attachments.prefix(maxDisplay))
    let overflow = attachments.count - maxDisplay

    LazyVGrid(columns: columns, spacing: 2) {
      ForEach(Array(displayAttachments.enumerated()), id: \.element.id) { index, attachment in
        ZStack {
          ImageThumbnailCell(attachment: attachment)
            .aspectRatio(1, contentMode: .fill)
            .clipped()

          if index == maxDisplay - 1 && overflow > 0 {
            Color.black.opacity(0.5)
            Text("+\(overflow)")
              .font(.title2.bold())
              .foregroundStyle(.white)
          }
        }
      }
    }
    .frame(maxWidth: 280)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var columns: [GridItem] {
    let count = min(attachments.count, maxDisplay)
    let columnCount = count <= 1 ? 1 : 2
    return Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
  }
}

struct ImageThumbnailCell: View {
  let attachment: Attachment

  var body: some View {
    if let data = attachment.thumbnailData, let nsImage = NSImage(data: data) {
      Image(nsImage: nsImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      Rectangle()
        .fill(Color(nsColor: .controlBackgroundColor))
        .overlay {
          Image(systemName: "photo")
            .foregroundStyle(.secondary)
        }
    }
  }
}
