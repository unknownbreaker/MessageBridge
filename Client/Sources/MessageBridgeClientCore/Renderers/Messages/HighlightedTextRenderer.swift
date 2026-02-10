import SwiftUI

/// Renderer for messages with any server-detected highlights (codes, phone numbers, mentions).
///
/// Styles each highlight type differently and shows a copy button for detected codes.
/// Priority 90: above PlainText (0), below LinkPreview (100).
public struct HighlightedTextRenderer: MessageRenderer {
  public let id = "highlighted-text"
  public let priority = 90

  public init() {}

  public func canRender(_ message: Message) -> Bool {
    guard let highlights = message.highlights else { return false }
    return !highlights.isEmpty
  }

  @MainActor
  public func render(_ message: Message) -> AnyView {
    AnyView(
      HighlightedTextView(
        text: message.text ?? "",
        highlights: message.highlights ?? [],
        codes: message.detectedCodes ?? []
      )
    )
  }
}

struct HighlightedTextView: View {
  let text: String
  let highlights: [TextHighlight]
  let codes: [DetectedCode]
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(attributedText)
        .textSelection(.enabled)

      if let code = codes.first {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(code.value, forType: .string)
          copied = true
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
            Text(copied ? "Copied!" : "Copy \(code.value)")
          }
          .font(.caption.weight(.medium))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Capsule().fill(.ultraThinMaterial))
          .overlay(Capsule().stroke(.separator))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var attributedText: AttributedString {
    var result = AttributedString(text)
    for highlight in highlights {
      guard let range = result.range(of: highlight.text) else { continue }
      switch highlight.type {
      case .code:
        result[range].backgroundColor = .yellow.opacity(0.3)
        result[range].font = .monospacedSystemFont(ofSize: 14, weight: .medium)
      case .phoneNumber:
        result[range].foregroundColor = .blue
      case .mention:
        result[range].font = .system(size: 14, weight: .semibold)
        result[range].foregroundColor = .accentColor
      case .link:
        result[range].foregroundColor = .blue
        result[range].underlineStyle = .single
      case .email:
        result[range].foregroundColor = .blue
      }
    }
    return result
  }
}
