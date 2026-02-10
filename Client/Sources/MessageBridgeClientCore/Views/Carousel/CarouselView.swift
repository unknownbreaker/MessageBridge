import SwiftUI

public struct CarouselView: View {
  let attachments: [Attachment]
  @State var currentIndex: Int
  @Environment(\.dismiss) private var dismiss

  public init(attachments: [Attachment], startIndex: Int = 0) {
    self.attachments = attachments
    self._currentIndex = State(
      initialValue: Self.clampedIndex(startIndex, count: attachments.count))
  }

  public var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if !attachments.isEmpty {
        ZoomableImageView(imageData: attachments[currentIndex].thumbnailData)
          .id(currentIndex)

        // Navigation arrows
        HStack {
          Button {
            withAnimation { currentIndex = max(currentIndex - 1, 0) }
          } label: {
            Image(systemName: "chevron.left.circle.fill")
              .font(.title)
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .opacity(currentIndex > 0 ? 1 : 0.3)
          .disabled(currentIndex == 0)
          .padding(.leading, 12)

          Spacer()

          Button {
            withAnimation { currentIndex = min(currentIndex + 1, attachments.count - 1) }
          } label: {
            Image(systemName: "chevron.right.circle.fill")
              .font(.title)
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .opacity(currentIndex < attachments.count - 1 ? 1 : 0.3)
          .disabled(currentIndex == attachments.count - 1)
          .padding(.trailing, 12)
        }
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
    .onKeyPress(.leftArrow) {
      if currentIndex > 0 { withAnimation { currentIndex -= 1 } }
      return .handled
    }
    .onKeyPress(.rightArrow) {
      if currentIndex < attachments.count - 1 { withAnimation { currentIndex += 1 } }
      return .handled
    }
    .onKeyPress(.escape) {
      dismiss()
      return .handled
    }
  }

  // MARK: - Testable helpers

  public static func clampedIndex(_ index: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return max(0, min(index, count - 1))
  }
}
