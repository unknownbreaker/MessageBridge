import SwiftUI

public struct PageIndicator: View {
  let currentIndex: Int
  let total: Int

  public init(currentIndex: Int, total: Int) {
    self.currentIndex = currentIndex
    self.total = total
  }

  public var body: some View {
    if total > 1 {
      HStack(spacing: 6) {
        ForEach(0..<total, id: \.self) { index in
          Circle()
            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.5))
            .frame(width: 7, height: 7)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Capsule().fill(.black.opacity(0.6)))
    }
  }
}
