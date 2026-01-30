import SwiftUI

/// Renderer for messages with rich link previews.
///
/// Displays an iMessage-style card with image, title, and domain.
/// Uses server-provided metadata extracted from iMessage's payload_data.
public struct LinkPreviewRenderer: MessageRenderer {
  public let id = "link-preview"
  public let priority = 100

  public init() {}

  public func canRender(_ message: Message) -> Bool {
    message.linkPreview != nil
  }

  @MainActor
  public func render(_ message: Message) -> AnyView {
    guard let preview = message.linkPreview else {
      return AnyView(EmptyView())
    }

    return AnyView(
      VStack(alignment: .leading, spacing: 4) {
        if let text = message.text, !text.isEmpty {
          Text(text)
            .textSelection(.enabled)
        }

        LinkPreviewCard(preview: preview)
      }
    )
  }
}

struct LinkPreviewCard: View {
  let preview: LinkPreview

  var body: some View {
    Link(destination: URL(string: preview.url) ?? URL(string: "about:blank")!) {
      VStack(alignment: .leading, spacing: 0) {
        if let imageData = preview.imageData,
          let nsImage = NSImage(data: imageData)
        {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: 280, maxHeight: 200)
            .clipped()
        }

        VStack(alignment: .leading, spacing: 4) {
          if let title = preview.title, !title.isEmpty {
            Text(title)
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.primary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }

          if let summary = preview.summary, !summary.isEmpty {
            Text(summary)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }

          HStack(spacing: 4) {
            Image(systemName: "link")
              .font(.caption2)
            Text(preview.domain)
              .font(.caption)
          }
          .foregroundStyle(.secondary)
        }
        .padding(10)
      }
      .frame(maxWidth: 280)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
      )
    }
    .buttonStyle(.plain)
  }
}
