import MessageBridgeClientCore
import SwiftUI

struct CarouselView: View {
  let attachments: [Attachment]
  @State var currentIndex: Int
  @Environment(\.dismiss) private var dismiss

  init(attachments: [Attachment], startIndex: Int = 0) {
    self.attachments = attachments
    self._currentIndex = State(
      initialValue: Self.clampedIndex(startIndex, count: attachments.count))
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if !attachments.isEmpty {
        TabView(selection: $currentIndex) {
          ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
            ZoomableImageView(imageData: attachment.thumbnailData)
              .tag(index)
          }
        }
        .tabViewStyle(.automatic)
      }

      // Close button
      VStack {
        HStack {
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.title)
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .padding()
        }
        Spacer()
      }

      // Page indicator
      VStack {
        Spacer()
        PageIndicator(currentIndex: currentIndex, total: attachments.count)
          .padding(.bottom, 16)
      }

      // Counter label
      VStack {
        Text("\(currentIndex + 1) of \(attachments.count)")
          .font(.caption)
          .foregroundStyle(.white.opacity(0.8))
          .padding(.top, 8)
        Spacer()
      }
    }
    .frame(minWidth: 500, minHeight: 400)
  }

  // MARK: - Testable helpers

  static func clampedIndex(_ index: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return max(0, min(index, count - 1))
  }
}
