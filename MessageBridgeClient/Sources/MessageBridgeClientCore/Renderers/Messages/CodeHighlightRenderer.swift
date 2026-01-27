import SwiftUI

/// Renderer for messages with detected verification/authentication codes.
///
/// Highlights detected codes in the message text and shows a "Copy Code"
/// button for quick clipboard access. Only activates when the server's
/// CodeDetector processor has identified codes in the message.
public struct CodeHighlightRenderer: MessageRenderer {
  public let id = "code-highlight"
  public let priority = 100

  public init() {}

  public func canRender(_ message: Message) -> Bool {
    guard let codes = message.detectedCodes else { return false }
    return !codes.isEmpty
  }

  @MainActor
  public func render(_ message: Message) -> AnyView {
    AnyView(
      CodeHighlightView(
        text: message.text ?? "",
        codes: message.detectedCodes ?? []
      )
    )
  }
}

struct CodeHighlightView: View {
  let text: String
  let codes: [DetectedCode]
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(highlightedText)
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

  private var highlightedText: AttributedString {
    var result = AttributedString(text)
    for code in codes {
      if let range = result.range(of: code.value) {
        result[range].backgroundColor = .yellow.opacity(0.3)
        result[range].font = .monospacedSystemFont(ofSize: 14, weight: .medium)
      }
    }
    return result
  }
}
