import SwiftUI

/// Renderer for messages containing URLs.
///
/// Displays the message text followed by a simple link card.
/// Uses the existing URLDetector for URL detection.
public struct LinkPreviewRenderer: MessageRenderer {
  public let id = "link-preview"
  public let priority = 100

  public init() {}

  public func canRender(_ message: Message) -> Bool {
    guard let text = message.text, !text.isEmpty else { return false }
    return URLDetector.containsURL(in: text)
  }

  @MainActor
  public func render(_ message: Message) -> AnyView {
    let text = message.text ?? ""
    let url = URLDetector.firstURL(in: text)

    return AnyView(
      VStack(alignment: .leading, spacing: 4) {
        Text(text)
          .textSelection(.enabled)

        if let url = url {
          Link(destination: url) {
            HStack(spacing: 8) {
              Image(systemName: "link")
                .foregroundStyle(.blue)
              VStack(alignment: .leading, spacing: 2) {
                Text(url.host ?? url.absoluteString)
                  .font(.caption)
                  .fontWeight(.medium)
                  .foregroundStyle(.primary)
                  .lineLimit(1)
                Text(url.absoluteString)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .frame(maxWidth: 280)
        }
      }
    )
  }
}
