import SwiftUI

/// Fallback renderer for any attachment type.
///
/// Displays each attachment as a document row with icon, filename, and size.
public struct DocumentRenderer: AttachmentRenderer {
  public let id = "document"
  public let priority = 0

  public init() {}

  public func canRender(_ attachments: [Attachment]) -> Bool {
    true
  }

  @MainActor
  public func render(_ attachments: [Attachment]) -> AnyView {
    AnyView(
      VStack(spacing: 4) {
        ForEach(attachments) { attachment in
          HStack(spacing: 12) {
            Image(systemName: Self.iconForExtension(attachment.filename))
              .font(.title2)
              .foregroundStyle(.secondary)
              .frame(width: 40, height: 40)
              .background(Color(nsColor: .controlBackgroundColor))
              .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
              Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
              Text(attachment.formattedSize)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }
          .padding(8)
          .background(Color(nsColor: .controlBackgroundColor))
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .frame(maxWidth: 250)
        }
      }
    )
  }

  static func iconForExtension(_ filename: String) -> String {
    let ext = (filename as NSString).pathExtension.lowercased()
    switch ext {
    case "pdf": return "doc.fill"
    case "doc", "docx": return "doc.text.fill"
    case "xls", "xlsx": return "tablecells.fill"
    case "ppt", "pptx": return "rectangle.split.3x3.fill"
    case "zip", "rar", "7z": return "doc.zipper"
    case "txt": return "doc.plaintext.fill"
    default: return "doc.fill"
    }
  }
}
