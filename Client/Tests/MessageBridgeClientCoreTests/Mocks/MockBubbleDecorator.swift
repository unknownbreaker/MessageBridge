import SwiftUI

@testable import MessageBridgeClientCore

final class MockBubbleDecorator: BubbleDecorator, @unchecked Sendable {
  let id: String
  let position: DecoratorPosition
  var shouldDecorateResult = true
  var shouldDecorateCallCount = 0

  init(id: String = "mock", position: DecoratorPosition = .below) {
    self.id = id
    self.position = position
  }

  func shouldDecorate(_ message: Message, context: DecoratorContext) -> Bool {
    shouldDecorateCallCount += 1
    return shouldDecorateResult
  }

  @MainActor
  func decorate(_ message: Message, context: DecoratorContext) -> AnyView {
    AnyView(Text("Mock decoration"))
  }
}
