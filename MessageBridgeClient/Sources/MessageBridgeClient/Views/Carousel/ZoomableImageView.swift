import SwiftUI

struct ZoomableImageView: View {
  let imageData: Data?

  @State private var scale: CGFloat = 1.0
  @State private var lastScale: CGFloat = 1.0
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero

  private let minScale: CGFloat = 1.0
  private let maxScale: CGFloat = 5.0

  var body: some View {
    Group {
      if let data = imageData, let nsImage = NSImage(data: data) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .scaleEffect(scale)
          .offset(offset)
          .gesture(magnificationGesture)
          .gesture(dragGesture)
          .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
              if scale > minScale {
                let (resetScale, resetOffset) = Self.clampAndReset()
                scale = resetScale
                lastScale = resetScale
                offset = resetOffset
                lastOffset = resetOffset
              } else {
                scale = 2.5
                lastScale = 2.5
              }
            }
          }
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var magnificationGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        scale = Self.clampedScale(lastScale * value, min: minScale, max: maxScale)
      }
      .onEnded { value in
        scale = Self.clampedScale(lastScale * value, min: minScale, max: maxScale)
        lastScale = scale
        if scale == minScale {
          withAnimation(.easeInOut(duration: 0.2)) {
            offset = .zero
            lastOffset = .zero
          }
        }
      }
  }

  private var dragGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        guard scale > minScale else { return }
        offset = CGSize(
          width: lastOffset.width + value.translation.width,
          height: lastOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        lastOffset = offset
      }
  }

  // MARK: - Testable helpers

  static func clampedScale(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, minVal), maxVal)
  }

  static func clampAndReset() -> (CGFloat, CGSize) {
    (1.0, .zero)
  }
}
