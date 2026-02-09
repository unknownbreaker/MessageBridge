import XCTest

@testable import MessageBridgeClientCore

final class ClientPinStorageTests: XCTestCase {

  override func setUp() {
    super.setUp()
    // Clear any persisted state before each test
    UserDefaults.standard.removeObject(forKey: "client.pinnedConversationIds")
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: "client.pinnedConversationIds")
    super.tearDown()
  }

  func testInitialStateIsEmpty() {
    let storage = ClientPinStorage()
    XCTAssertTrue(storage.orderedIds.isEmpty)
  }

  func testPinAddsToEnd() {
    let storage = ClientPinStorage()
    storage.pin(id: "chat1")
    storage.pin(id: "chat2")

    XCTAssertEqual(storage.orderedIds, ["chat1", "chat2"])
  }

  func testPinDuplicateIsNoOp() {
    let storage = ClientPinStorage()
    storage.pin(id: "chat1")
    storage.pin(id: "chat1")

    XCTAssertEqual(storage.orderedIds, ["chat1"])
  }

  func testUnpinRemoves() {
    let storage = ClientPinStorage()
    storage.pin(id: "chat1")
    storage.pin(id: "chat2")
    storage.unpin(id: "chat1")

    XCTAssertEqual(storage.orderedIds, ["chat2"])
  }

  func testUnpinNonExistentIsNoOp() {
    let storage = ClientPinStorage()
    storage.pin(id: "chat1")
    storage.unpin(id: "chat99")

    XCTAssertEqual(storage.orderedIds, ["chat1"])
  }

  func testIsPinned() {
    let storage = ClientPinStorage()
    storage.pin(id: "chat1")

    XCTAssertTrue(storage.isPinned(id: "chat1"))
    XCTAssertFalse(storage.isPinned(id: "chat2"))
  }

  func testPersistsAcrossInstances() {
    // Pin in one instance
    let storage1 = ClientPinStorage()
    storage1.pin(id: "chat1")
    storage1.pin(id: "chat2")

    // Load in a new instance
    let storage2 = ClientPinStorage()
    XCTAssertEqual(storage2.orderedIds, ["chat1", "chat2"])
  }

  func testUnpinPersists() {
    let storage1 = ClientPinStorage()
    storage1.pin(id: "chat1")
    storage1.pin(id: "chat2")
    storage1.unpin(id: "chat1")

    let storage2 = ClientPinStorage()
    XCTAssertEqual(storage2.orderedIds, ["chat2"])
  }
}
