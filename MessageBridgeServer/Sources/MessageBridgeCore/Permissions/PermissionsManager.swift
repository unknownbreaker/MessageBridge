import AppKit
import Contacts
import Foundation

/// Represents a system permission required by the app
public struct PermissionStatus: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let description: String
  public let isGranted: Bool
  public let settingsURL: URL?
  public let requiresManualSetup: Bool

  public init(
    id: String, name: String, description: String, isGranted: Bool, settingsURL: URL?,
    requiresManualSetup: Bool = false
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.isGranted = isGranted
    self.settingsURL = settingsURL
    self.requiresManualSetup = requiresManualSetup
  }
}

/// Manages checking and requesting system permissions
public actor PermissionsManager {
  public static let shared = PermissionsManager()

  private init() {}

  // MARK: - System Settings URLs

  private let fullDiskAccessURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
  private let contactsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")
  private let automationURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
  private let accessibilityURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

  // MARK: - Public API

  /// Check all required permissions and return their status
  public func checkAllPermissions() async -> [PermissionStatus] {
    var permissions: [PermissionStatus] = []

    // Full Disk Access - required to read Messages database
    let fullDiskAccess = checkFullDiskAccess()
    permissions.append(
      PermissionStatus(
        id: "fullDiskAccess",
        name: "Full Disk Access",
        description: "Required to read the Messages database (chat.db)",
        isGranted: fullDiskAccess,
        settingsURL: fullDiskAccessURL,
        requiresManualSetup: true
      ))

    // Contacts - required to look up contact names
    let contactsAccess = await checkContactsAccess()
    permissions.append(
      PermissionStatus(
        id: "contacts",
        name: "Contacts",
        description: "Required to display contact names instead of phone numbers",
        isGranted: contactsAccess,
        settingsURL: contactsURL
      ))

    // Automation (Messages.app) - required to send messages via AppleScript
    let messagesAutomationAccess = await checkMessagesAutomationAccess()
    permissions.append(
      PermissionStatus(
        id: "automationMessages",
        name: "Automation (Messages.app)",
        description: "Required to send messages through the Messages app",
        isGranted: messagesAutomationAccess,
        settingsURL: automationURL
      ))

    // Accessibility - optional, only needed if duplicate group chats with same participants exist
    let accessibilityAccess = checkAccessibilityAccess()
    permissions.append(
      PermissionStatus(
        id: "accessibility",
        name: "Accessibility (Optional)",
        description:
          "Only needed for rare edge case: multiple group chats with identical participants",
        isGranted: accessibilityAccess,
        settingsURL: accessibilityURL,
        requiresManualSetup: true
      ))

    return permissions
  }

  /// Check if all required permissions are granted
  public func allPermissionsGranted() async -> Bool {
    let permissions = await checkAllPermissions()
    return permissions.allSatisfy { $0.isGranted }
  }

  /// Open System Settings to the specified URL
  public nonisolated func openSettings(url: URL?) {
    guard let url = url else { return }
    NSWorkspace.shared.open(url)
  }

  // MARK: - Individual Permission Checks

  /// Check if Full Disk Access is granted by trying to read the Messages database
  private nonisolated func checkFullDiskAccess() -> Bool {
    let chatDBPath = NSHomeDirectory() + "/Library/Messages/chat.db"
    // Actually try to open the file - isReadableFile can be cached
    guard let handle = FileHandle(forReadingAtPath: chatDBPath) else {
      return false
    }
    handle.closeFile()
    return true
  }

  /// Check if Contacts access is granted
  private func checkContactsAccess() async -> Bool {
    let status = CNContactStore.authorizationStatus(for: .contacts)

    // Handle all possible authorization statuses
    // .notDetermined = 0, .restricted = 1, .denied = 2, .authorized = 3
    // On macOS 15+ / iOS 18+: .fullAccess, .limitedAccess may also be present
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      // Try to request access
      do {
        let store = CNContactStore()
        return try await store.requestAccess(for: .contacts)
      } catch {
        return false
      }
    case .restricted, .denied:
      return false
    @unknown default:
      // Handle future cases (like .fullAccess, .limitedAccess on newer OS)
      // If rawValue >= 3, treat as some form of access granted
      return status.rawValue >= 3
    }
  }

  /// Check if Automation access for Messages.app is granted
  /// This triggers the permission prompt by attempting to communicate with Messages
  private func checkMessagesAutomationAccess() async -> Bool {
    let script = """
      tell application "Messages"
          return name
      end tell
      """

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
      _ = appleScript.executeAndReturnError(&error)
      if error == nil {
        return true
      }

      if let errorInfo = error,
        let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
      {
        // -1743 is "not authorized" for automation
        // -600 is "application isn't running" which is OK (permission granted)
        if errorNumber == -600 {
          return true
        }
      }
    }

    return false
  }

  /// Check if Accessibility access is granted (required to send keystrokes via System Events)
  private nonisolated func checkAccessibilityAccess() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }
}
