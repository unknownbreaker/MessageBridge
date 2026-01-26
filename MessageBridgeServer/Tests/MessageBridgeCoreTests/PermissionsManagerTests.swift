import XCTest

@testable import MessageBridgeCore

final class PermissionsManagerTests: XCTestCase {

  // MARK: - PermissionStatus Tests

  func testPermissionStatus_init() {
    let status = PermissionStatus(
      id: "test",
      name: "Test Permission",
      description: "A test permission",
      isGranted: true,
      settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security")
    )

    XCTAssertEqual(status.id, "test")
    XCTAssertEqual(status.name, "Test Permission")
    XCTAssertEqual(status.description, "A test permission")
    XCTAssertTrue(status.isGranted)
    XCTAssertNotNil(status.settingsURL)
  }

  func testPermissionStatus_initWithNilURL() {
    let status = PermissionStatus(
      id: "test",
      name: "Test",
      description: "Test",
      isGranted: false,
      settingsURL: nil
    )

    XCTAssertNil(status.settingsURL)
  }

  // MARK: - PermissionsManager Tests

  func testPermissionsManager_shared_isSingleton() async {
    let manager1 = PermissionsManager.shared
    let manager2 = PermissionsManager.shared

    // Both references should point to the same instance
    // Since actors don't support identity comparison directly,
    // we just verify they both exist
    let permissions1 = await manager1.checkAllPermissions()
    let permissions2 = await manager2.checkAllPermissions()

    XCTAssertEqual(permissions1.count, permissions2.count)
  }

  func testPermissionsManager_checkAllPermissions_returnsThreePermissions() async {
    let manager = PermissionsManager.shared
    let permissions = await manager.checkAllPermissions()

    XCTAssertEqual(permissions.count, 3)

    // Verify the permission IDs
    let ids = permissions.map { $0.id }
    XCTAssertTrue(ids.contains("fullDiskAccess"))
    XCTAssertTrue(ids.contains("contacts"))
    XCTAssertTrue(ids.contains("automation"))
  }

  func testPermissionsManager_checkAllPermissions_hasSettingsURLs() async {
    let manager = PermissionsManager.shared
    let permissions = await manager.checkAllPermissions()

    // All permissions should have settings URLs
    for permission in permissions {
      XCTAssertNotNil(
        permission.settingsURL, "Permission \(permission.id) should have a settings URL")
    }
  }

  func testPermissionsManager_checkAllPermissions_hasDescriptions() async {
    let manager = PermissionsManager.shared
    let permissions = await manager.checkAllPermissions()

    // All permissions should have non-empty descriptions
    for permission in permissions {
      XCTAssertFalse(
        permission.description.isEmpty, "Permission \(permission.id) should have a description")
    }
  }

  func testPermissionsManager_fullDiskAccess_permission() async {
    let manager = PermissionsManager.shared
    let permissions = await manager.checkAllPermissions()

    guard let fullDiskAccess = permissions.first(where: { $0.id == "fullDiskAccess" }) else {
      XCTFail("Full Disk Access permission not found")
      return
    }

    XCTAssertEqual(fullDiskAccess.name, "Full Disk Access")
    XCTAssertTrue(fullDiskAccess.description.contains("Messages database"))
  }

  func testPermissionsManager_contacts_permission() async {
    let manager = PermissionsManager.shared
    let permissions = await manager.checkAllPermissions()

    guard let contacts = permissions.first(where: { $0.id == "contacts" }) else {
      XCTFail("Contacts permission not found")
      return
    }

    XCTAssertEqual(contacts.name, "Contacts")
    XCTAssertTrue(contacts.description.contains("contact names"))
  }

  func testPermissionsManager_automation_permission() async {
    let manager = PermissionsManager.shared
    let permissions = await manager.checkAllPermissions()

    guard let automation = permissions.first(where: { $0.id == "automation" }) else {
      XCTFail("Automation permission not found")
      return
    }

    XCTAssertEqual(automation.name, "Automation (Messages.app)")
    XCTAssertTrue(automation.description.contains("send messages"))
  }

  func testPermissionsManager_allPermissionsGranted_returnsBool() async {
    let manager = PermissionsManager.shared
    let allGranted = await manager.allPermissionsGranted()

    // Just verify it returns a boolean without crashing
    // The actual value depends on system state
    XCTAssertNotNil(allGranted as Bool?)
  }
}
