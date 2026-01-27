# AttachmentRenderer Protocol Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract attachment rendering from hardcoded switch into protocol-based renderers with group-aware AttachmentRendererRegistry and image gallery support.

**Architecture:** AttachmentRenderer protocol with group-based rendering, priority selection via AttachmentRendererRegistry. 5 renderers: DocumentRenderer (fallback), SingleImageRenderer, VideoRenderer, AudioRenderer, ImageGalleryRenderer.

**Tech Stack:** SwiftUI, Swift protocols

---

### Task 1: AttachmentRenderer Protocol + Mock

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/AttachmentRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Mocks/MockAttachmentRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Protocols/AttachmentRendererTests.swift`

**Step 1: Write tests**

```swift
// Tests/MessageBridgeClientCoreTests/Mocks/MockAttachmentRenderer.swift
import SwiftUI
@testable import MessageBridgeClientCore

final class MockAttachmentRenderer: AttachmentRenderer, @unchecked Sendable {
    let id: String
    let priority: Int
    var canRenderResult = true
    var canRenderCallCount = 0
    var renderCallCount = 0

    init(id: String = "mock", priority: Int = 0) {
        self.id = id
        self.priority = priority
    }

    func canRender(_ attachments: [Attachment]) -> Bool {
        canRenderCallCount += 1
        return canRenderResult
    }

    @MainActor
    func render(_ attachments: [Attachment]) -> AnyView {
        renderCallCount += 1
        return AnyView(Text("Mock: \(attachments.count) attachments"))
    }
}
```

```swift
// Tests/MessageBridgeClientCoreTests/Protocols/AttachmentRendererTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class AttachmentRendererTests: XCTestCase {
    func testMockRenderer_hasId() {
        let renderer = MockAttachmentRenderer(id: "test")
        XCTAssertEqual(renderer.id, "test")
    }

    func testMockRenderer_hasPriority() {
        let renderer = MockAttachmentRenderer(priority: 50)
        XCTAssertEqual(renderer.priority, 50)
    }

    func testMockRenderer_canRender_returnsConfiguredValue() {
        let renderer = MockAttachmentRenderer()
        renderer.canRenderResult = false
        XCTAssertFalse(renderer.canRender([]))
        renderer.canRenderResult = true
        XCTAssertTrue(renderer.canRender([]))
    }

    func testMockRenderer_canRender_incrementsCallCount() {
        let renderer = MockAttachmentRenderer()
        _ = renderer.canRender([])
        _ = renderer.canRender([])
        XCTAssertEqual(renderer.canRenderCallCount, 2)
    }
}
```

**Step 2: Implement protocol**

```swift
// Sources/MessageBridgeClientCore/Protocols/AttachmentRenderer.swift
import SwiftUI

/// Protocol for rendering groups of message attachments.
///
/// Implementations handle different attachment configurations (single image,
/// image gallery, video, audio, documents). The AttachmentRendererRegistry
/// selects the highest-priority renderer whose `canRender` returns true.
///
/// Renderers receive all attachments for a message as a group, enabling
/// multi-attachment layouts like image grids.
public protocol AttachmentRenderer: Identifiable, Sendable {
    /// Unique identifier for this renderer
    var id: String { get }

    /// Priority for selection. Higher = checked first.
    var priority: Int { get }

    /// Whether this renderer can handle this group of attachments.
    func canRender(_ attachments: [Attachment]) -> Bool

    /// Render the attachment group.
    @MainActor func render(_ attachments: [Attachment]) -> AnyView
}
```

**Step 3: Run tests, commit**

```bash
cd /Users/robertyang/Documents/Repos/Personal/MessageBridge/MessageBridgeClient && swift test
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Protocols/AttachmentRenderer.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Mocks/MockAttachmentRenderer.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Protocols/AttachmentRendererTests.swift
git commit -m "feat(client): add AttachmentRenderer protocol and mock"
```

---

### Task 2: AttachmentRendererRegistry

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/AttachmentRendererRegistry.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Registries/AttachmentRendererRegistryTests.swift`

**Step 1: Write tests**

```swift
// Tests/MessageBridgeClientCoreTests/Registries/AttachmentRendererRegistryTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class AttachmentRendererRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AttachmentRendererRegistry.shared.reset()
    }

    override func tearDown() {
        AttachmentRendererRegistry.shared.reset()
        super.tearDown()
    }

    func testShared_isSingleton() {
        XCTAssertTrue(AttachmentRendererRegistry.shared === AttachmentRendererRegistry.shared)
    }

    func testRegister_addsRenderer() {
        AttachmentRendererRegistry.shared.register(MockAttachmentRenderer(id: "a"))
        XCTAssertEqual(AttachmentRendererRegistry.shared.all.count, 1)
    }

    func testAll_returnsRegistered() {
        AttachmentRendererRegistry.shared.register(MockAttachmentRenderer(id: "a"))
        AttachmentRendererRegistry.shared.register(MockAttachmentRenderer(id: "b"))
        let ids = AttachmentRendererRegistry.shared.all.map { $0.id }
        XCTAssertTrue(ids.contains("a"))
        XCTAssertTrue(ids.contains("b"))
    }

    func testReset_clears() {
        AttachmentRendererRegistry.shared.register(MockAttachmentRenderer(id: "a"))
        AttachmentRendererRegistry.shared.reset()
        XCTAssertTrue(AttachmentRendererRegistry.shared.all.isEmpty)
    }

    func testRenderer_selectsHighestPriorityMatch() {
        let low = MockAttachmentRenderer(id: "low", priority: 0)
        let high = MockAttachmentRenderer(id: "high", priority: 100)
        AttachmentRendererRegistry.shared.register(low)
        AttachmentRendererRegistry.shared.register(high)
        let selected = AttachmentRendererRegistry.shared.renderer(for: [])
        XCTAssertEqual(selected.id, "high")
    }

    func testRenderer_skipsNonMatching() {
        let noMatch = MockAttachmentRenderer(id: "no", priority: 100)
        noMatch.canRenderResult = false
        let fallback = MockAttachmentRenderer(id: "fall", priority: 0)
        AttachmentRendererRegistry.shared.register(noMatch)
        AttachmentRendererRegistry.shared.register(fallback)
        let selected = AttachmentRendererRegistry.shared.renderer(for: [])
        XCTAssertEqual(selected.id, "fall")
    }

    func testRenderer_emptyRegistry_returnsDocumentRenderer() {
        let selected = AttachmentRendererRegistry.shared.renderer(for: [])
        XCTAssertEqual(selected.id, "document")
    }
}
```

**Step 2: Implement**

```swift
// Sources/MessageBridgeClientCore/Registries/AttachmentRendererRegistry.swift
import Foundation

/// Singleton registry for attachment renderers.
///
/// Selects the highest-priority renderer whose `canRender` returns true.
/// Falls back to DocumentRenderer when no match is found.
public final class AttachmentRendererRegistry: @unchecked Sendable {
    public static let shared = AttachmentRendererRegistry()

    private var renderers: [any AttachmentRenderer] = []
    private let lock = NSLock()

    private init() {}

    public func register(_ renderer: any AttachmentRenderer) {
        lock.lock()
        defer { lock.unlock() }
        renderers.append(renderer)
    }

    public func renderer(for attachments: [Attachment]) -> any AttachmentRenderer {
        lock.lock()
        defer { lock.unlock() }
        return renderers
            .sorted { $0.priority > $1.priority }
            .first { $0.canRender(attachments) }
            ?? DocumentRenderer()
    }

    public var all: [any AttachmentRenderer] {
        lock.lock()
        defer { lock.unlock() }
        return renderers
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        renderers.removeAll()
    }
}
```

Note: This depends on DocumentRenderer (Task 3) for the fallback. Implement together.

**Step 3: Run tests, commit (after Task 3)**

---

### Task 3: DocumentRenderer (fallback) + SingleImageRenderer

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/DocumentRenderer.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/SingleImageRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/DocumentRendererTests.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/SingleImageRendererTests.swift`

**Context:** The existing `DocumentAttachmentView` and `ImageAttachmentView` are defined in `MessageBridgeClient/Sources/MessageBridgeClient/Views/AttachmentView.swift`. They are in the **app target**, not Core. The renderers in Core cannot reference these views directly.

**Solution:** The renderers' `canRender` logic lives in Core (testable). The `render` method must be in the app target OR the existing views must be moved to Core. Since the views use `@EnvironmentObject var viewModel: MessagesViewModel` (which is in Core), they CAN be moved.

**Approach:** Keep renderers in Core. The `render` methods will create basic SwiftUI views. The existing ImageAttachmentView etc. stay in the app target for now — we'll reference their pattern but implement fresh views in the renderers. This avoids coupling and keeps things testable.

**DocumentRenderer:**

```swift
// Sources/MessageBridgeClientCore/Renderers/Attachments/DocumentRenderer.swift
import SwiftUI

/// Fallback renderer for any attachment type.
///
/// Displays each attachment as a document with icon, filename, and size.
public struct DocumentRenderer: AttachmentRenderer {
    public let id = "document"
    public let priority = 0

    public init() {}

    public func canRender(_ attachments: [Attachment]) -> Bool {
        true  // Fallback — always renders
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        AnyView(
            VStack(spacing: 4) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 12) {
                        Image(systemName: iconForExtension(attachment.filename))
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .background(Color(.controlBackgroundColor))
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
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 250)
                }
            }
        )
    }

    private func iconForExtension(_ filename: String) -> String {
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
```

**SingleImageRenderer:**

```swift
// Sources/MessageBridgeClientCore/Renderers/Attachments/SingleImageRenderer.swift
import SwiftUI

/// Renderer for a single image attachment.
///
/// Shows thumbnail with tap-to-enlarge support.
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
    @State private var isShowingFullImage = false
    @State private var fullImageData: Data?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let thumbnailData = attachment.thumbnailData,
               let nsImage = NSImage(data: thumbnailData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 250, maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { isShowingFullImage = true }
            } else {
                // Placeholder
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                    Text(attachment.filename)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $isShowingFullImage) {
            if let data = fullImageData, let nsImage = NSImage(data: data) {
                VStack {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                    Button("Close") { isShowingFullImage = false }
                        .padding()
                }
                .frame(minWidth: 400, minHeight: 300)
            } else if isLoading {
                ProgressView("Loading...")
                    .frame(width: 200, height: 200)
            }
        }
    }
}
```

**Tests:**

```swift
// Tests/MessageBridgeClientCoreTests/Renderers/DocumentRendererTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class DocumentRendererTests: XCTestCase {
    let renderer = DocumentRenderer()

    func testId() { XCTAssertEqual(renderer.id, "document") }
    func testPriority() { XCTAssertEqual(renderer.priority, 0) }
    func testCanRender_alwaysTrue() { XCTAssertTrue(renderer.canRender([])) }
    func testCanRender_withAnyAttachment() {
        XCTAssertTrue(renderer.canRender([makeAttachment(mime: "application/pdf")]))
    }

    private func makeAttachment(mime: String) -> Attachment {
        Attachment(id: 1, guid: "g", filename: "file.pdf", mimeType: mime, size: 1000, isOutgoing: false, isSticker: false)
    }
}
```

```swift
// Tests/MessageBridgeClientCoreTests/Renderers/SingleImageRendererTests.swift
import XCTest
@testable import MessageBridgeClientCore

final class SingleImageRendererTests: XCTestCase {
    let renderer = SingleImageRenderer()

    func testId() { XCTAssertEqual(renderer.id, "single-image") }
    func testPriority() { XCTAssertEqual(renderer.priority, 50) }

    func testCanRender_singleImage_true() {
        XCTAssertTrue(renderer.canRender([makeAttachment(mime: "image/jpeg")]))
    }

    func testCanRender_singleVideo_false() {
        XCTAssertFalse(renderer.canRender([makeAttachment(mime: "video/mp4")]))
    }

    func testCanRender_twoImages_false() {
        let a = makeAttachment(mime: "image/jpeg")
        XCTAssertFalse(renderer.canRender([a, a]))
    }

    func testCanRender_empty_false() {
        XCTAssertFalse(renderer.canRender([]))
    }

    private func makeAttachment(mime: String) -> Attachment {
        Attachment(id: 1, guid: "g", filename: "photo.jpg", mimeType: mime, size: 1000, isOutgoing: false, isSticker: false)
    }
}
```

**Step: Create all files, run tests, commit Tasks 2+3 together**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Registries/AttachmentRendererRegistry.swift \
       MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/ \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Registries/AttachmentRendererRegistryTests.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/
git commit -m "feat(client): add AttachmentRendererRegistry, DocumentRenderer, SingleImageRenderer"
```

---

### Task 4: VideoRenderer + AudioRenderer

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/VideoRenderer.swift`
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/AudioRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/VideoRendererTests.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/AudioRendererTests.swift`

**VideoRenderer:**

```swift
public struct VideoRenderer: AttachmentRenderer {
    public let id = "video"
    public let priority = 50

    public init() {}

    public func canRender(_ attachments: [Attachment]) -> Bool {
        !attachments.isEmpty && attachments.allSatisfy { $0.isVideo }
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        AnyView(
            VStack(spacing: 4) {
                ForEach(attachments) { attachment in
                    VideoThumbnailView(attachment: attachment)
                }
            }
        )
    }
}

struct VideoThumbnailView: View {
    let attachment: Attachment

    var body: some View {
        ZStack {
            if let thumbnailData = attachment.thumbnailData,
               let nsImage = NSImage(data: thumbnailData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 250, maxHeight: 200)
            } else {
                Rectangle()
                    .fill(Color(.controlBackgroundColor))
                    .frame(width: 200, height: 150)
                    .overlay {
                        Image(systemName: "video.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }

            // Play button overlay
            Circle()
                .fill(.black.opacity(0.6))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                        .font(.title3)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            Text(attachment.formattedSize)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(6)
        }
    }
}
```

**AudioRenderer:**

```swift
public struct AudioRenderer: AttachmentRenderer {
    public let id = "audio"
    public let priority = 50

    public init() {}

    public func canRender(_ attachments: [Attachment]) -> Bool {
        !attachments.isEmpty && attachments.allSatisfy { $0.isAudio }
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        AnyView(
            VStack(spacing: 4) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 40, height: 40)
                            .background(Color.blue.opacity(0.1))
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
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 250)
                }
            }
        )
    }
}
```

**Tests:**

```swift
// VideoRendererTests.swift
final class VideoRendererTests: XCTestCase {
    let renderer = VideoRenderer()

    func testId() { XCTAssertEqual(renderer.id, "video") }
    func testPriority() { XCTAssertEqual(renderer.priority, 50) }

    func testCanRender_singleVideo_true() {
        XCTAssertTrue(renderer.canRender([makeAttachment(mime: "video/mp4")]))
    }
    func testCanRender_multipleVideos_true() {
        let v = makeAttachment(mime: "video/mp4")
        XCTAssertTrue(renderer.canRender([v, v]))
    }
    func testCanRender_image_false() {
        XCTAssertFalse(renderer.canRender([makeAttachment(mime: "image/jpeg")]))
    }
    func testCanRender_mixed_false() {
        XCTAssertFalse(renderer.canRender([
            makeAttachment(mime: "video/mp4"),
            makeAttachment(mime: "image/jpeg")
        ]))
    }
    func testCanRender_empty_false() {
        XCTAssertFalse(renderer.canRender([]))
    }

    private func makeAttachment(mime: String) -> Attachment {
        Attachment(id: 1, guid: "g", filename: "vid.mp4", mimeType: mime, size: 5000, isOutgoing: false, isSticker: false)
    }
}
```

```swift
// AudioRendererTests.swift
final class AudioRendererTests: XCTestCase {
    let renderer = AudioRenderer()

    func testId() { XCTAssertEqual(renderer.id, "audio") }
    func testPriority() { XCTAssertEqual(renderer.priority, 50) }

    func testCanRender_singleAudio_true() {
        XCTAssertTrue(renderer.canRender([makeAttachment(mime: "audio/mpeg")]))
    }
    func testCanRender_image_false() {
        XCTAssertFalse(renderer.canRender([makeAttachment(mime: "image/jpeg")]))
    }
    func testCanRender_empty_false() {
        XCTAssertFalse(renderer.canRender([]))
    }

    private func makeAttachment(mime: String) -> Attachment {
        Attachment(id: 1, guid: "g", filename: "audio.mp3", mimeType: mime, size: 2000, isOutgoing: false, isSticker: false)
    }
}
```

**Commit:**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/VideoRenderer.swift \
       MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/AudioRenderer.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/VideoRendererTests.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/AudioRendererTests.swift
git commit -m "feat(client): add VideoRenderer and AudioRenderer"
```

---

### Task 5: ImageGalleryRenderer

**Files:**
- Create: `MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/ImageGalleryRenderer.swift`
- Create: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/ImageGalleryRendererTests.swift`

**ImageGalleryRenderer:**

```swift
public struct ImageGalleryRenderer: AttachmentRenderer {
    public let id = "image-gallery"
    public let priority = 100

    public init() {}

    public func canRender(_ attachments: [Attachment]) -> Bool {
        attachments.filter { $0.isImage }.count >= 2
    }

    @MainActor
    public func render(_ attachments: [Attachment]) -> AnyView {
        let images = attachments.filter { $0.isImage }
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
            }
        }
        .frame(maxWidth: 280)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var columns: [GridItem] {
        let count = min(attachments.count, maxDisplay)
        let columnCount = count <= 1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
    }
}

struct ImageThumbnailCell: View {
    let attachment: Attachment

    var body: some View {
        if let data = attachment.thumbnailData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color(.controlBackgroundColor))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
```

**Tests:**

```swift
final class ImageGalleryRendererTests: XCTestCase {
    let renderer = ImageGalleryRenderer()

    func testId() { XCTAssertEqual(renderer.id, "image-gallery") }
    func testPriority() { XCTAssertEqual(renderer.priority, 100) }

    func testCanRender_twoImages_true() {
        let a = makeAttachment(mime: "image/jpeg")
        XCTAssertTrue(renderer.canRender([a, a]))
    }

    func testCanRender_threeImages_true() {
        let a = makeAttachment(mime: "image/jpeg")
        XCTAssertTrue(renderer.canRender([a, a, a]))
    }

    func testCanRender_singleImage_false() {
        XCTAssertFalse(renderer.canRender([makeAttachment(mime: "image/jpeg")]))
    }

    func testCanRender_noImages_false() {
        XCTAssertFalse(renderer.canRender([makeAttachment(mime: "video/mp4")]))
    }

    func testCanRender_mixedWithTwoImages_true() {
        let img = makeAttachment(mime: "image/jpeg")
        let vid = makeAttachment(mime: "video/mp4")
        XCTAssertTrue(renderer.canRender([img, vid, img]))
    }

    func testCanRender_empty_false() {
        XCTAssertFalse(renderer.canRender([]))
    }

    private func makeAttachment(mime: String) -> Attachment {
        Attachment(id: Int64.random(in: 1...999), guid: UUID().uuidString, filename: "img.jpg", mimeType: mime, size: 1000, isOutgoing: false, isSticker: false)
    }
}
```

**Commit:**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/Renderers/Attachments/ImageGalleryRenderer.swift \
       MessageBridgeClient/Tests/MessageBridgeClientCoreTests/Renderers/ImageGalleryRendererTests.swift
git commit -m "feat(client): add ImageGalleryRenderer with grid layout"
```

---

### Task 6: Integrate into MessageBubble and register renderers

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift`
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/App/MessageBridgeApp.swift`

**MessageBubble change (around lines 125-129):**

```swift
// OLD:
if message.hasAttachments {
    ForEach(message.attachments) { attachment in
        AttachmentView(attachment: attachment)
    }
}

// NEW:
if message.hasAttachments {
    AttachmentRendererRegistry.shared.renderer(for: message.attachments)
        .render(message.attachments)
}
```

**App registration — add to MessageBridgeApp init:**

```swift
private func setupAttachmentRenderers() {
    AttachmentRendererRegistry.shared.register(DocumentRenderer())
    AttachmentRendererRegistry.shared.register(SingleImageRenderer())
    AttachmentRendererRegistry.shared.register(VideoRenderer())
    AttachmentRendererRegistry.shared.register(AudioRenderer())
    AttachmentRendererRegistry.shared.register(ImageGalleryRenderer())
}
```

Call `setupAttachmentRenderers()` in init, after `setupRenderers()`.

**Build and test:**

```bash
cd /Users/robertyang/Documents/Repos/Personal/MessageBridge/MessageBridgeClient && swift build && swift test
```

**Commit:**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/
git commit -m "feat(client): integrate AttachmentRendererRegistry into MessageBubble"
```

---

### Task 7: Update CLAUDE.md migration table

**Files:**
- Modify: `CLAUDE.md`

Change `Client Attachments` row from `🔴 Not migrated` to `✅ Migrated`.

```bash
git add CLAUDE.md
git commit -m "docs: mark Client Attachments as migrated in CLAUDE.md"
```
