import XCTest

@testable import MessageBridgeClientCore

final class ActionRegistryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    ActionRegistry.shared.reset()
  }
  override func tearDown() {
    ActionRegistry.shared.reset()
    super.tearDown()
  }

  func testShared_isSingleton() {
    XCTAssertTrue(ActionRegistry.shared === ActionRegistry.shared)
  }

  func testRegister_addsAction() {
    ActionRegistry.shared.register(MockMessageAction(id: "a"))
    XCTAssertEqual(ActionRegistry.shared.all.count, 1)
  }

  func testReset_clears() {
    ActionRegistry.shared.register(MockMessageAction(id: "a"))
    ActionRegistry.shared.reset()
    XCTAssertTrue(ActionRegistry.shared.all.isEmpty)
  }

  func testAvailableActions_filtersUnavailable() {
    let available = MockMessageAction(id: "yes")
    let unavailable = MockMessageAction(id: "no")
    unavailable.isAvailableResult = false
    ActionRegistry.shared.register(available)
    ActionRegistry.shared.register(unavailable)
    let msg = makeMessage()
    let result = ActionRegistry.shared.availableActions(for: msg)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].id, "yes")
  }

  func testAvailableActions_preservesRegistrationOrder() {
    ActionRegistry.shared.register(MockMessageAction(id: "first"))
    ActionRegistry.shared.register(MockMessageAction(id: "second"))
    ActionRegistry.shared.register(MockMessageAction(id: "third"))
    let result = ActionRegistry.shared.availableActions(for: makeMessage())
    XCTAssertEqual(result.map { $0.id }, ["first", "second", "third"])
  }

  func testAvailableActions_emptyWhenNoneAvailable() {
    let action = MockMessageAction(id: "a")
    action.isAvailableResult = false
    ActionRegistry.shared.register(action)
    XCTAssertTrue(ActionRegistry.shared.availableActions(for: makeMessage()).isEmpty)
  }

  private func makeMessage() -> Message {
    Message(
      id: 1, guid: "g1", text: "Hi", date: Date(), isFromMe: true, handleId: nil,
      conversationId: "c1")
  }
}
