import MessageBridgeClientCore
import SwiftUI

/// Main attachment view that dispatches to specific views based on attachment type
struct AttachmentView: View {
  let attachment: Attachment
  @EnvironmentObject var viewModel: MessagesViewModel

  var body: some View {
    Group {
      switch attachment.attachmentType {
      case .image:
        ImageAttachmentView(attachment: attachment)
      case .video:
        VideoAttachmentView(attachment: attachment)
      case .audio:
        AudioAttachmentView(attachment: attachment)
      case .document:
        DocumentAttachmentView(attachment: attachment)
      }
    }
  }
}

// MARK: - Image Attachment

struct ImageAttachmentView: View {
  let attachment: Attachment
  @State private var isShowingFullImage = false
  @State private var fullImageData: Data?
  @State private var isLoading = false
  @EnvironmentObject var viewModel: MessagesViewModel

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
          .onTapGesture {
            isShowingFullImage = true
            loadFullImage()
          }
      } else {
        // Placeholder for images without thumbnails
        HStack(spacing: 8) {
          Image(systemName: "photo")
            .foregroundStyle(.secondary)
          Text(attachment.filename)
            .lineLimit(1)
          Spacer()
          Text(attachment.formattedSize)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
          isShowingFullImage = true
          loadFullImage()
        }
      }
    }
    .sheet(isPresented: $isShowingFullImage) {
      FullImageView(
        attachment: attachment,
        imageData: fullImageData,
        isLoading: isLoading
      )
    }
  }

  private func loadFullImage() {
    guard fullImageData == nil else { return }
    isLoading = true
    Task {
      do {
        let data = try await viewModel.fetchAttachment(id: attachment.id)
        await MainActor.run {
          fullImageData = data
          isLoading = false
        }
      } catch {
        await MainActor.run {
          isLoading = false
        }
      }
    }
  }
}

/// Full-screen image viewer
struct FullImageView: View {
  let attachment: Attachment
  let imageData: Data?
  let isLoading: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack {
      HStack {
        Text(attachment.filename)
          .font(.headline)
        Spacer()
        Button("Done") {
          dismiss()
        }
      }
      .padding()

      if isLoading {
        Spacer()
        ProgressView("Loading...")
        Spacer()
      } else if let data = imageData, let nsImage = NSImage(data: data) {
        ScrollView([.horizontal, .vertical]) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
        }
      } else if let thumbnailData = attachment.thumbnailData,
        let nsImage = NSImage(data: thumbnailData)
      {
        // Fallback to thumbnail
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        Spacer()
        Text("Unable to load image")
          .foregroundStyle(.secondary)
        Spacer()
      }
    }
    .frame(minWidth: 400, minHeight: 300)
  }
}

// MARK: - Video Attachment

struct VideoAttachmentView: View {
  let attachment: Attachment
  @EnvironmentObject var viewModel: MessagesViewModel

  var body: some View {
    ZStack {
      if let thumbnailData = attachment.thumbnailData,
        let nsImage = NSImage(data: thumbnailData)
      {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: 250, maxHeight: 250)
      } else {
        Rectangle()
          .fill(Color(nsColor: .controlBackgroundColor))
          .frame(width: 200, height: 150)
      }

      // Play button overlay
      Circle()
        .fill(.black.opacity(0.6))
        .frame(width: 50, height: 50)
        .overlay {
          Image(systemName: "play.fill")
            .foregroundStyle(.white)
            .font(.title2)
        }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(alignment: .bottomTrailing) {
      Text(attachment.formattedSize)
        .font(.caption2)
        .padding(4)
        .background(.black.opacity(0.6))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(8)
    }
    .onTapGesture {
      // TODO: Open video in AVPlayer or QuickLook
      logInfo("Video playback not yet implemented")
    }
  }
}

// MARK: - Audio Attachment

struct AudioAttachmentView: View {
  let attachment: Attachment

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "waveform")
        .font(.title2)
        .foregroundStyle(.blue)
        .frame(width: 40, height: 40)
        .background(Color.blue.opacity(0.1))
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(attachment.filename)
          .lineLimit(1)
        Text(attachment.formattedSize)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "play.circle.fill")
        .font(.title)
        .foregroundStyle(.blue)
    }
    .padding(12)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .onTapGesture {
      // TODO: Play audio
      logInfo("Audio playback not yet implemented")
    }
  }
}

// MARK: - Document Attachment

struct DocumentAttachmentView: View {
  let attachment: Attachment
  @EnvironmentObject var viewModel: MessagesViewModel

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: iconForDocument)
        .font(.title2)
        .foregroundStyle(colorForDocument)
        .frame(width: 40, height: 40)
        .background(colorForDocument.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 2) {
        Text(attachment.filename)
          .lineLimit(1)
        Text(attachment.formattedSize)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "arrow.down.circle")
        .font(.title2)
        .foregroundStyle(.secondary)
    }
    .padding(12)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .onTapGesture {
      // TODO: Download and open file
      logInfo("Document download not yet implemented")
    }
  }

  private var iconForDocument: String {
    let ext = (attachment.filename as NSString).pathExtension.lowercased()
    switch ext {
    case "pdf":
      return "doc.fill"
    case "doc", "docx":
      return "doc.text.fill"
    case "xls", "xlsx":
      return "tablecells.fill"
    case "ppt", "pptx":
      return "rectangle.split.3x3.fill"
    case "zip", "rar", "7z":
      return "doc.zipper"
    case "txt":
      return "doc.plaintext.fill"
    default:
      return "doc.fill"
    }
  }

  private var colorForDocument: Color {
    let ext = (attachment.filename as NSString).pathExtension.lowercased()
    switch ext {
    case "pdf":
      return .red
    case "doc", "docx":
      return .blue
    case "xls", "xlsx":
      return .green
    case "ppt", "pptx":
      return .orange
    case "zip", "rar", "7z":
      return .purple
    default:
      return .gray
    }
  }
}

#Preview("Image Attachment") {
  let attachment = Attachment(
    id: 1,
    guid: "test",
    filename: "photo.jpg",
    mimeType: "image/jpeg",
    size: 1_500_000,
    isOutgoing: false,
    isSticker: false
  )
  return AttachmentView(attachment: attachment)
    .environmentObject(MessagesViewModel())
    .padding()
}

#Preview("Document Attachment") {
  let attachment = Attachment(
    id: 1,
    guid: "test",
    filename: "document.pdf",
    mimeType: "application/pdf",
    size: 2_500_000,
    isOutgoing: false,
    isSticker: false
  )
  return DocumentAttachmentView(attachment: attachment)
    .environmentObject(MessagesViewModel())
    .padding()
    .frame(width: 300)
}
