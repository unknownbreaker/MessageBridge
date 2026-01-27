import SwiftUI
import XCTest

@testable import MessageBridgeClientCore

// MARK: - Mock Plugin

struct MockComposerPlugin: ComposerPlugin {
  let id: String
  let icon: String
  let keyboardShortcut: KeyEquivalent? = nil
  let modifiers: EventModifiers = []

  var shouldShowToolbar: Bool = true
  var activateHandler: (@MainActor () async -> Void)?

  func showsToolbarButton(context: any ComposerContext) -> Bool {
    shouldShowToolbar
  }

  @MainActor
  func activate(context: any ComposerContext) async {
    await activateHandler?()
  }
}

// MARK: - Mock Context

@MainActor
final class MockComposerContext: ComposerContext {
  var text: String = ""
  var attachments: [DraftAttachment] = []
  var insertedTexts: [String] = []
  var addedAttachments: [DraftAttachment] = []
  var removedAttachmentIds: [String] = []
  var presentedSheet = false
  var dismissedSheet = false
  var sendCalled = false

  func insertText(_ text: String) {
    insertedTexts.append(text)
    self.text += text
  }

  func addAttachment(_ attachment: DraftAttachment) {
    addedAttachments.append(attachment)
    attachments.append(attachment)
  }

  func removeAttachment(_ id: String) {
    removedAttachmentIds.append(id)
    attachments.removeAll { $0.id == id }
  }

  func presentSheet(_ view: AnyView) {
    presentedSheet = true
  }

  func dismissSheet() {
    dismissedSheet = true
  }

  func send() async {
    sendCalled = true
  }
}

// MARK: - Tests

final class ComposerPluginTests: XCTestCase {
  func testPluginConformsToIdentifiable() {
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip")
    XCTAssertEqual(plugin.id, "test")
  }

  func testPluginIcon() {
    let plugin = MockComposerPlugin(id: "test", icon: "mic")
    XCTAssertEqual(plugin.icon, "mic")
  }

  @MainActor
  func testPluginShowsToolbarButton() {
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip", shouldShowToolbar: true)
    let context = MockComposerContext()
    XCTAssertTrue(plugin.showsToolbarButton(context: context))
  }

  @MainActor
  func testPluginHidesToolbarButton() {
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip", shouldShowToolbar: false)
    let context = MockComposerContext()
    XCTAssertFalse(plugin.showsToolbarButton(context: context))
  }

  @MainActor
  func testPluginActivate() async {
    var activated = false
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip") {
      activated = true
    }
    let context = MockComposerContext()
    await plugin.activate(context: context)
    XCTAssertTrue(activated)
  }
}

final class ComposerContextTests: XCTestCase {
  @MainActor
  func testInsertText() {
    let context = MockComposerContext()
    context.insertText("Hello")
    XCTAssertEqual(context.text, "Hello")
    XCTAssertEqual(context.insertedTexts, ["Hello"])
  }

  @MainActor
  func testInsertTextAppends() {
    let context = MockComposerContext()
    context.text = "Hi "
    context.insertText("there")
    XCTAssertEqual(context.text, "Hi there")
  }

  @MainActor
  func testAddAttachment() {
    let context = MockComposerContext()
    let attachment = DraftAttachment(
      url: URL(fileURLWithPath: "/tmp/test.png"),
      type: .image,
      fileName: "test.png"
    )
    context.addAttachment(attachment)
    XCTAssertEqual(context.attachments.count, 1)
    XCTAssertEqual(context.addedAttachments.count, 1)
  }

  @MainActor
  func testRemoveAttachment() {
    let context = MockComposerContext()
    let attachment = DraftAttachment(
      id: "att-1",
      url: URL(fileURLWithPath: "/tmp/test.png"),
      type: .image,
      fileName: "test.png"
    )
    context.attachments = [attachment]
    context.removeAttachment("att-1")
    XCTAssertTrue(context.attachments.isEmpty)
    XCTAssertEqual(context.removedAttachmentIds, ["att-1"])
  }

  @MainActor
  func testSend() async {
    let context = MockComposerContext()
    await context.send()
    XCTAssertTrue(context.sendCalled)
  }

  @MainActor
  func testPresentAndDismissSheet() {
    let context = MockComposerContext()
    context.presentSheet(AnyView(EmptyView()))
    XCTAssertTrue(context.presentedSheet)
    context.dismissSheet()
    XCTAssertTrue(context.dismissedSheet)
  }
}
