import LinkPresentation
import MessageBridgeClientCore
import SwiftUI

/// SwiftUI view that displays a rich link preview for a URL
/// Uses Apple's LinkPresentation framework for native appearance
struct LinkPreviewView: View {
  let url: URL
  @State private var metadata: LPLinkMetadata?
  @State private var isLoading = true
  @State private var loadFailed = false

  var body: some View {
    Group {
      if let metadata = metadata {
        LinkPreviewCard(metadata: metadata, url: url)
          .frame(maxWidth: 280)
      } else if isLoading {
        // Loading placeholder
        HStack(spacing: 8) {
          ProgressView()
            .scaleEffect(0.7)
          Text("Loading preview...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: 280)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      } else if loadFailed {
        // Fallback: show URL as clickable link
        SimpleLinkView(url: url)
      }
    }
    .task {
      await loadMetadata()
    }
  }

  private func loadMetadata() async {
    // Check cache first
    if let cached = await LinkPreviewCache.shared.metadata(for: url) {
      self.metadata = cached
      self.isLoading = false
      return
    }

    // Fetch metadata
    let provider = LPMetadataProvider()
    do {
      let fetchedMetadata = try await provider.startFetchingMetadata(for: url)
      await LinkPreviewCache.shared.store(fetchedMetadata, for: url)
      await MainActor.run {
        self.metadata = fetchedMetadata
        self.isLoading = false
      }
    } catch {
      logDebug("Failed to fetch link preview for \(url): \(error.localizedDescription)")
      await MainActor.run {
        self.loadFailed = true
        self.isLoading = false
      }
    }
  }
}

/// NSViewRepresentable wrapper for LPLinkView
/// Provides native link preview appearance matching Apple Messages
struct LinkPreviewCard: NSViewRepresentable {
  let metadata: LPLinkMetadata
  let url: URL

  func makeNSView(context: Context) -> LPLinkView {
    let linkView = LPLinkView(metadata: metadata)
    return linkView
  }

  func updateNSView(_ nsView: LPLinkView, context: Context) {
    nsView.metadata = metadata
  }
}

/// Simple fallback link view when metadata loading fails
struct SimpleLinkView: View {
  let url: URL

  var body: some View {
    Button(action: openURL) {
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
    .buttonStyle(.plain)
    .frame(maxWidth: 280)
  }

  private func openURL() {
    NSWorkspace.shared.open(url)
  }
}

#Preview("Link Preview Loading") {
  LinkPreviewView(url: URL(string: "https://apple.com")!)
    .padding()
}

#Preview("Simple Link Fallback") {
  SimpleLinkView(url: URL(string: "https://example.com/very/long/path/to/page")!)
    .padding()
}
