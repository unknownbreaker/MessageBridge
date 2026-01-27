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
  @State private var isShowingFullImage = false
  @State private var fullImageData: Data?
  @State private var isLoading = false

  var body: some View {
    Group {
      if let thumbnailData = attachment.thumbnailData,
        let nsImage = NSImage(data: thumbnailData)
      {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: 250, maxHeight: 250)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .onTapGesture { isShowingFullImage = true }
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
    .sheet(isPresented: $isShowingFullImage) {
      if let data = fullImageData, let nsImage = NSImage(data: data) {
        VStack {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding()
          Button("Close") { isShowingFullImage = false }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
      } else if isLoading {
        ProgressView("Loading...")
          .frame(width: 200, height: 200)
      }
    }
  }
}
