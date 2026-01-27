import SwiftUI
import XCTest

@testable import MessageBridgeClientCore

// Re-use MockComposerPlugin from ComposerPluginTests (same test target, visible)

final class ComposerRegistryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    ComposerRegistry.shared.reset()
  }

  func testStartsEmpty() {
    XCTAssertTrue(ComposerRegistry.shared.all.isEmpty)
  }

  func testRegister() {
    let plugin = MockComposerPlugin(id: "test", icon: "paperclip")
    ComposerRegistry.shared.register(plugin)
    XCTAssertEqual(ComposerRegistry.shared.all.count, 1)
    XCTAssertEqual(ComposerRegistry.shared.all.first?.id, "test")
  }

  func testRegisterMultiple_preservesOrder() {
    ComposerRegistry.shared.register(MockComposerPlugin(id: "a", icon: "a"))
    ComposerRegistry.shared.register(MockComposerPlugin(id: "b", icon: "b"))
    ComposerRegistry.shared.register(MockComposerPlugin(id: "c", icon: "c"))
    let ids = ComposerRegistry.shared.all.map(\.id)
    XCTAssertEqual(ids, ["a", "b", "c"])
  }

  func testUnregister() {
    ComposerRegistry.shared.register(MockComposerPlugin(id: "a", icon: "a"))
    ComposerRegistry.shared.register(MockComposerPlugin(id: "b", icon: "b"))
    ComposerRegistry.shared.unregister("a")
    XCTAssertEqual(ComposerRegistry.shared.all.count, 1)
    XCTAssertEqual(ComposerRegistry.shared.all.first?.id, "b")
  }

  func testUnregister_nonexistent_noOp() {
    ComposerRegistry.shared.register(MockComposerPlugin(id: "a", icon: "a"))
    ComposerRegistry.shared.unregister("zzz")
    XCTAssertEqual(ComposerRegistry.shared.all.count, 1)
  }

  func testReset() {
    ComposerRegistry.shared.register(MockComposerPlugin(id: "a", icon: "a"))
    ComposerRegistry.shared.reset()
    XCTAssertTrue(ComposerRegistry.shared.all.isEmpty)
  }

  func testThreadSafety() {
    let expectation = expectation(description: "concurrent access")
    expectation.expectedFulfillmentCount = 100

    for i in 0..<100 {
      DispatchQueue.global().async {
        ComposerRegistry.shared.register(MockComposerPlugin(id: "p\(i)", icon: "star"))
        _ = ComposerRegistry.shared.all
        expectation.fulfill()
      }
    }

    wait(for: [expectation], timeout: 5)
    XCTAssertEqual(ComposerRegistry.shared.all.count, 100)
  }
}
