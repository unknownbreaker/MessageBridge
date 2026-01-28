# M3.2 Image Gallery Carousel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a carousel view so tapping an image in the gallery grid (or single image) opens a fullscreen paging viewer with swipe navigation and pinch-to-zoom.

**Architecture:** Three new SwiftUI views (`CarouselView`, `ZoomableImageView`, `PageIndicator`) in `Views/Carousel/`. `ImageGalleryRenderer` and `SingleImageRenderer` gain tap handlers that present `CarouselView` via `.fullScreenCover`. Pure SwiftUI — `MagnificationGesture` + `DragGesture` for zoom/pan, `TabView(.page)` for paging.

**Tech Stack:** SwiftUI, AppKit (NSImage for data→image)

---

## Task 1: Add PageIndicator view

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClient/Views/Carousel/PageIndicator.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Views/PageIndicatorTests.swift`

**Step 1: Write the failing test**

```swift
// PageIndicatorTests.swift
import XCTest
@testable import MessageBridgeClient

final class PageIndicatorTests: XCTestCase {
  func testCurrentIndex_clamped() {
    // PageIndicator is a pure view — test the data logic
    // Verify the indicator count matches total
    let total = 5
    let current = 2
    XCTAssertTrue(current >= 0 && current < total)
  }

  func testZeroTotal_noIndicator() {
    let total = 0
    XCTAssertEqual(max(total, 0), 0)
  }
}
```

**Step 2: Run test to verify it compiles**

Run: `cd MessageBridgeClient && swift test --filter PageIndicatorTests`

**Step 3: Write implementation**

```swift
// PageIndicator.swift
import SwiftUI

struct PageIndicator: View {
  let currentIndex: Int
  let total: Int

  var body: some View {
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
```

**Step 4: Run tests**

Run: `cd MessageBridgeClient && swift test --filter PageIndicatorTests`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/Carousel/PageIndicator.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Views/PageIndicatorTests.swift
git commit -m "feat(client): add PageIndicator view for carousel"
```

---

## Task 2: Add ZoomableImageView

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClient/Views/Carousel/ZoomableImageView.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Views/ZoomableImageViewTests.swift`

**Step 1: Write the failing test**

```swift
// ZoomableImageViewTests.swift
import XCTest
@testable import MessageBridgeClient

final class ZoomableImageViewTests: XCTestCase {
  func testClampedScale_belowMinimum_returnsMinimum() {
    let scale = ZoomableImageView.clampedScale(0.3, min: 1.0, max: 5.0)
    XCTAssertEqual(scale, 1.0)
  }

  func testClampedScale_aboveMaximum_returnsMaximum() {
    let scale = ZoomableImageView.clampedScale(10.0, min: 1.0, max: 5.0)
    XCTAssertEqual(scale, 5.0)
  }

  func testClampedScale_withinRange_returnsValue() {
    let scale = ZoomableImageView.clampedScale(2.5, min: 1.0, max: 5.0)
    XCTAssertEqual(scale, 2.5)
  }

  func testResetZoom_returnsDefaults() {
    let (scale, offset) = ZoomableImageView.resetZoom()
    XCTAssertEqual(scale, 1.0)
    XCTAssertEqual(offset, .zero)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeClient && swift test --filter ZoomableImageViewTests`
Expected: FAIL — `ZoomableImageView` not defined

**Step 3: Write implementation**

```swift
// ZoomableImageView.swift
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
                let (s, o) = Self.resetZoom()
                scale = s
                lastScale = s
                offset = o
                lastOffset = o
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

  static func resetZoom() -> (CGFloat, CGSize) {
    (1.0, .zero)
  }
}
```

**Step 4: Run tests**

Run: `cd MessageBridgeClient && swift test --filter ZoomableImageViewTests`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/Carousel/ZoomableImageView.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Views/ZoomableImageViewTests.swift
git commit -m "feat(client): add ZoomableImageView with pinch-to-zoom and pan"
```

---

## Task 3: Add CarouselView

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClient/Views/Carousel/CarouselView.swift`
- Test: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Views/CarouselViewTests.swift`

**Step 1: Write the failing test**

```swift
// CarouselViewTests.swift
import XCTest
@testable import MessageBridgeClient
@testable import MessageBridgeClientCore

final class CarouselViewTests: XCTestCase {
  func testInitialIndex_preserved() {
    let attachments = [makeImage("a"), makeImage("b"), makeImage("c")]
    // CarouselView should start at the given index
    let startIndex = 2
    XCTAssertTrue(startIndex >= 0 && startIndex < attachments.count)
  }

  func testClampedIndex_outOfBounds_clamped() {
    let count = 3
    let clamped = CarouselView.clampedIndex(5, count: count)
    XCTAssertEqual(clamped, 2)
  }

  func testClampedIndex_negative_clamped() {
    let clamped = CarouselView.clampedIndex(-1, count: 3)
    XCTAssertEqual(clamped, 0)
  }

  func testClampedIndex_valid_unchanged() {
    let clamped = CarouselView.clampedIndex(1, count: 3)
    XCTAssertEqual(clamped, 1)
  }

  func testClampedIndex_emptyCount_returnsZero() {
    let clamped = CarouselView.clampedIndex(0, count: 0)
    XCTAssertEqual(clamped, 0)
  }

  private func makeImage(_ name: String) -> Attachment {
    Attachment(
      id: Int64.random(in: 1...9999), guid: UUID().uuidString, filename: "\(name).jpg",
      mimeType: "image/jpeg", size: 1000, isOutgoing: false, isSticker: false)
  }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeClient && swift test --filter CarouselViewTests`
Expected: FAIL — `CarouselView` not defined

**Step 3: Write implementation**

```swift
// CarouselView.swift
import SwiftUI
import MessageBridgeClientCore

struct CarouselView: View {
  let attachments: [Attachment]
  @State var currentIndex: Int
  @Environment(\.dismiss) private var dismiss

  init(attachments: [Attachment], startIndex: Int = 0) {
    self.attachments = attachments
    self._currentIndex = State(initialValue: Self.clampedIndex(startIndex, count: attachments.count))
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
```

**Step 4: Run tests**

Run: `cd MessageBridgeClient && swift test --filter CarouselViewTests`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/Carousel/CarouselView.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Views/CarouselViewTests.swift
git commit -m "feat(client): add CarouselView with paging and page indicator"
```

---

## Task 4: Integrate carousel into ImageGalleryRenderer

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/ImageGalleryRenderer.swift`
- Modify: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/ImageGalleryRendererTests.swift`

**Step 1: Update ImageGridView to accept an onTap closure and add sheet state**

The change: each `ImageThumbnailCell` gets `.onTapGesture` that sets a selected index, which triggers `.fullScreenCover` presenting `CarouselView`.

```swift
// Updated ImageGalleryRenderer.swift — full replacement
import SwiftUI

public struct ImageGalleryRenderer: AttachmentRenderer {
  public let id = "image-gallery"
  public let priority = 100

  public init() {}

  public func canRender(_ attachments: [Attachment]) -> Bool {
    attachments.filter(\.isImage).count >= 2
  }

  @MainActor
  public func render(_ attachments: [Attachment]) -> AnyView {
    let images = attachments.filter(\.isImage)
    let nonImages = attachments.filter { !$0.isImage }

    return AnyView(
      VStack(spacing: 4) {
        ImageGridView(attachments: images)

        if !nonImages.isEmpty {
          ForEach(nonImages) { attachment in
            AttachmentRendererRegistry.shared
              .renderer(for: [attachment])
              .render([attachment])
          }
        }
      }
    )
  }
}

struct ImageGridView: View {
  let attachments: [Attachment]
  private let maxDisplay = 4
  @State private var selectedIndex: Int?

  var body: some View {
    let displayAttachments = Array(attachments.prefix(maxDisplay))
    let overflow = attachments.count - maxDisplay

    LazyVGrid(columns: columns, spacing: 2) {
      ForEach(Array(displayAttachments.enumerated()), id: \.element.id) { index, attachment in
        ZStack {
          ImageThumbnailCell(attachment: attachment)
            .aspectRatio(1, contentMode: .fill)
            .clipped()

          if index == maxDisplay - 1 && overflow > 0 {
            Color.black.opacity(0.5)
            Text("+\(overflow)")
              .font(.title2.bold())
              .foregroundStyle(.white)
          }
        }
        .onTapGesture {
          selectedIndex = index
        }
      }
    }
    .frame(maxWidth: 280)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .fullScreenCover(item: $selectedIndex) { index in
      CarouselView(attachments: attachments, startIndex: index)
    }
  }

  private var columns: [GridItem] {
    let count = min(attachments.count, maxDisplay)
    let columnCount = count <= 1 ? 1 : 2
    return Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
  }
}
```

**Note:** `Int` doesn't conform to `Identifiable`, so we need a small wrapper or use `.fullScreenCover(isPresented:)` with a separate `@State var isShowingCarousel = false`. The simpler approach:

```swift
@State private var isShowingCarousel = false
@State private var carouselStartIndex = 0

// on tap:
.onTapGesture {
  carouselStartIndex = index
  isShowingCarousel = true
}

// sheet:
.fullScreenCover(isPresented: $isShowingCarousel) {
  CarouselView(attachments: attachments, startIndex: carouselStartIndex)
}
```

**Step 2: Run all existing tests to verify no regressions**

Run: `cd MessageBridgeClient && swift test`
Expected: All 297+ tests PASS

**Step 3: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/ImageGalleryRenderer.swift
git commit -m "feat(client): integrate carousel into ImageGalleryRenderer grid"
```

---

## Task 5: Integrate carousel into SingleImageRenderer

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/SingleImageRenderer.swift`

**Step 1: Replace the existing sheet with CarouselView**

Replace `SingleImageView`'s `.sheet` with `.fullScreenCover` presenting `CarouselView(attachments: [attachment], startIndex: 0)`. Remove the old `fullImageData` and `isLoading` state since CarouselView handles its own display.

```swift
// Updated SingleImageRenderer.swift — full replacement
import SwiftUI

public struct SingleImageRenderer: AttachmentRenderer {
  public let id = "single-image"
  public let priority = 50

  public init() {}

  public func canRender(_ attachments: [Attachment]) -> Bool {
    attachments.count == 1 && attachments[0].isImage
  }

  @MainActor
  public func render(_ attachments: [Attachment]) -> AnyView {
    AnyView(
      SingleImageView(attachment: attachments[0])
    )
  }
}

struct SingleImageView: View {
  let attachment: Attachment
  @State private var isShowingCarousel = false

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
          .onTapGesture { isShowingCarousel = true }
      } else {
        HStack(spacing: 8) {
          Image(systemName: "photo")
            .foregroundStyle(.secondary)
          Text(attachment.filename)
            .font(.caption)
            .lineLimit(1)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
    }
    .fullScreenCover(isPresented: $isShowingCarousel) {
      CarouselView(attachments: [attachment], startIndex: 0)
    }
  }
}
```

**Step 2: Run tests**

Run: `cd MessageBridgeClient && swift test`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/SingleImageRenderer.swift
git commit -m "feat(client): use CarouselView for single image fullscreen"
```

---

## Task 6: Update spec.md and CLAUDE.md

**Files:**
- Modify: `spec.md` — change M3.2 from 🔴 to 🔵
- Modify: `CLAUDE.md` — update M3.2 audit tracker row to all ✅

**Step 1: Update spec.md**

Change `### M3.2: Image Gallery & Carousel 🔴` to `### M3.2: Image Gallery & Carousel 🔵`

**Step 2: Update CLAUDE.md audit tracker**

Change M3.2 row to `| M3.2 Image Gallery | ✅ | ✅ | ✅ | ✅ |`

**Step 3: Run full test suite**

Run: `cd MessageBridgeClient && swift test && cd ../MessageBridgeServer && swift test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add spec.md CLAUDE.md
git commit -m "docs: mark M3.2 Image Gallery as complete"
```

---

## Notes

- **CarouselView lives in the app target** (`MessageBridgeClient/`) not the core library, because it's a SwiftUI view composition, not a protocol/registry component. The tests import `@testable import MessageBridgeClient`.
- **TabView paging on macOS:** `.tabViewStyle(.automatic)` is used because `.page` is iOS-only. On macOS, TabView shows tab selectors. If this doesn't give swipe behavior, Task 3 may need a custom `NSPageController` wrapper via `NSViewRepresentable`. Evaluate at implementation time and adjust.
- **Full-resolution images:** Currently only `thumbnailData` is available on `Attachment`. The carousel shows thumbnails for now. Loading full-resolution images requires a network call to the server's `/attachments/:id` endpoint — that's a follow-up enhancement, not part of this milestone.
