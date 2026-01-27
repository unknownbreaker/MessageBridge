import SwiftUI

@testable import MessageBridgeClientCore

final class MockMessageAction: MessageAction, @unchecked Sendable {
  let id: String
  let title: String
  let icon: String
  let destructive: Bool
  var isAvailableResult = true
  var performCallCount = 0

  init(
    id: String = "mock",
    title: String = "Mock",
    icon: String = "star",
    destructive: Bool = false
  ) {
    self.id = id
    self.title = title
    self.icon = icon
    self.destructive = destructive
  }

  func isAvailable(for message: Message) -> Bool {
    isAvailableResult
  }

  @MainActor
  func perform(on message: Message) async {
    performCallCount += 1
  }
}
