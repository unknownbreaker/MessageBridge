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
