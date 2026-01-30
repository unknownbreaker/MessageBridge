import SwiftUI

/// Renderer for messages with rich link previews.
///
/// Displays an iMessage-style card with image, title, and domain.
/// Uses server-provided metadata extracted from iMessage's payload_data.
/// The URL is stripped from the message text — if the text is only a URL,
/// no text is shown. If there's additional text, it appears below the card.
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

    let strippedText = Self.stripURL(preview.url, from: message.text)

    return AnyView(
      LinkPreviewCard(preview: preview, strippedText: strippedText, isFromMe: message.isFromMe)
    )
  }

  /// Remove the link preview URL from the message text.
  /// Returns nil if the remaining text is empty (i.e., the message was only a URL).
  static func stripURL(_ url: String, from text: String?) -> String? {
    guard let text = text else { return nil }
    let stripped = text.replacingOccurrences(of: url, with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripped.isEmpty ? nil : stripped
  }
}

struct LinkPreviewCard: View {
  let preview: LinkPreview
  let strippedText: String?
  let isFromMe: Bool

  var body: some View {
    Link(destination: URL(string: preview.url) ?? URL(string: "about:blank")!) {
      VStack(alignment: .leading, spacing: 0) {
        // Preview image — bleeds to edges of the bubble
        if let imageData = preview.imageData,
          let nsImage = NSImage(data: imageData)
        {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: 280, maxHeight: 200)
            .clipped()
        }

        // Title and domain
        VStack(alignment: .leading, spacing: 2) {
          if let title = preview.title, !title.isEmpty {
            Text(title)
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(isFromMe ? .white : .primary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }

          HStack(spacing: 4) {
            Image(systemName: "link")
              .font(.caption2)
            Text(preview.domain)
              .font(.caption)
          }
          .foregroundStyle(isFromMe ? .white.opacity(0.7) : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)

        // Stripped message text below the card
        if let text = strippedText {
          Divider()
            .opacity(0.3)
          Text(text)
            .font(.body)
            .foregroundStyle(isFromMe ? .white : .primary)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
      }
      .frame(maxWidth: 280)
    }
    .buttonStyle(.plain)
  }
}
