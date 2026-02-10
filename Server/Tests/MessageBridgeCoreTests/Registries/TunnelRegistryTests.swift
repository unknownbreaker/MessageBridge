import XCTest

@testable import MessageBridgeCore

final class TunnelRegistryTests: XCTestCase {

  override func setUp() {
    super.setUp()
    TunnelRegistry.shared.reset()
  }

  override func tearDown() {
    TunnelRegistry.shared.reset()
    super.tearDown()
  }

  func testRegisterAndGet() async {
    let mock = MockTunnelProvider(id: "test-provider")
    TunnelRegistry.shared.register(mock)

    let retrieved = TunnelRegistry.shared.get("test-provider")
    XCTAssertNotNil(retrieved)
    XCTAssertEqual(retrieved?.id, "test-provider")
  }

  func testGetNonExistent() {
    let retrieved = TunnelRegistry.shared.get("does-not-exist")
    XCTAssertNil(retrieved)
  }

  func testAll() async {
    let mock1 = MockTunnelProvider(id: "provider-1")
    let mock2 = MockTunnelProvider(id: "provider-2")

    TunnelRegistry.shared.register(mock1)
    TunnelRegistry.shared.register(mock2)

    let all = TunnelRegistry.shared.all
    XCTAssertEqual(all.count, 2)

    let ids = Set(all.map { $0.id })
    XCTAssertTrue(ids.contains("provider-1"))
    XCTAssertTrue(ids.contains("provider-2"))
  }

  func testCount() async {
    XCTAssertEqual(TunnelRegistry.shared.count, 0)

    TunnelRegistry.shared.register(MockTunnelProvider(id: "p1"))
    XCTAssertEqual(TunnelRegistry.shared.count, 1)

    TunnelRegistry.shared.register(MockTunnelProvider(id: "p2"))
    XCTAssertEqual(TunnelRegistry.shared.count, 2)
  }

  func testContains() async {
    XCTAssertFalse(TunnelRegistry.shared.contains("test"))

    TunnelRegistry.shared.register(MockTunnelProvider(id: "test"))
    XCTAssertTrue(TunnelRegistry.shared.contains("test"))
  }

  func testRemove() async {
    let mock = MockTunnelProvider(id: "to-remove")
    TunnelRegistry.shared.register(mock)
    XCTAssertTrue(TunnelRegistry.shared.contains("to-remove"))

    let removed = TunnelRegistry.shared.remove("to-remove")
    XCTAssertNotNil(removed)
    XCTAssertFalse(TunnelRegistry.shared.contains("to-remove"))
  }

  func testReset() async {
    TunnelRegistry.shared.register(MockTunnelProvider(id: "p1"))
    TunnelRegistry.shared.register(MockTunnelProvider(id: "p2"))
    XCTAssertEqual(TunnelRegistry.shared.count, 2)

    TunnelRegistry.shared.reset()
    XCTAssertEqual(TunnelRegistry.shared.count, 0)
  }

  func testRegisterReplaces() async {
    let mock1 = MockTunnelProvider(id: "same-id", displayName: "First")
    let mock2 = MockTunnelProvider(id: "same-id", displayName: "Second")

    TunnelRegistry.shared.register(mock1)
    TunnelRegistry.shared.register(mock2)

    XCTAssertEqual(TunnelRegistry.shared.count, 1)

    let retrieved = TunnelRegistry.shared.get("same-id")
    XCTAssertEqual(retrieved?.displayName, "Second")
  }
}
