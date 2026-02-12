import Foundation
import Security

/// Errors that can occur during Keychain operations
public enum KeychainError: LocalizedError {
  case duplicateItem
  case itemNotFound
  case unexpectedStatus(OSStatus)
  case invalidData

  public var errorDescription: String? {
    switch self {
    case .duplicateItem:
      return "Item already exists in Keychain"
    case .itemNotFound:
      return "Item not found in Keychain"
    case .unexpectedStatus(let status):
      return "Keychain error: \(status)"
    case .invalidData:
      return "Invalid data format"
    }
  }
}

/// Protocol for Keychain operations (for testability)
public protocol KeychainProtocol: Sendable {
  func saveAPIKey(_ key: String) throws
  func retrieveAPIKey() throws -> String
  func deleteAPIKey() throws
  func generateAPIKey() -> String
}

/// Manages secure storage of API keys in the macOS Keychain
public struct KeychainManager: KeychainProtocol {
  private let service = "com.messagebridge.server"
  private let account = "api-key"

  public init() {}

  /// Save an API key to the Keychain
  public func saveAPIKey(_ key: String) throws {
    guard let data = key.data(using: .utf8) else {
      throw KeychainError.invalidData
    }

    let baseAttributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    var addQuery = baseAttributes
    addQuery[kSecValueData as String] = data
    if let access = KeychainAccess.createPermissive(label: "MessageBridge Server API Key") {
      addQuery[kSecAttrAccess as String] = access
    }

    var status = SecItemAdd(addQuery as CFDictionary, nil)

    // If item exists, delete and re-add with permissive ACL so future
    // rebuilds (new code signature) can access it without a prompt.
    // Falls back to update if the delete is denied (old ACL restricts access).
    if status == errSecDuplicateItem {
      let deleteStatus = SecItemDelete(baseAttributes as CFDictionary)
      if deleteStatus == errSecSuccess {
        status = SecItemAdd(addQuery as CFDictionary, nil)
      } else {
        status = SecItemUpdate(
          baseAttributes as CFDictionary,
          [kSecValueData as String: data] as CFDictionary)
      }
    }

    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  /// Retrieve the API key from the Keychain
  public func retrieveAPIKey() throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      if status == errSecItemNotFound {
        throw KeychainError.itemNotFound
      }
      throw KeychainError.unexpectedStatus(status)
    }

    guard let data = result as? Data,
      let key = String(data: data, encoding: .utf8)
    else {
      throw KeychainError.invalidData
    }

    return key
  }

  /// Delete the API key from the Keychain
  public func deleteAPIKey() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let status = SecItemDelete(query as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  /// Generate a new random API key
  public func generateAPIKey() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  /// Get or create an API key (convenience method)
  public func getOrCreateAPIKey() throws -> String {
    do {
      return try retrieveAPIKey()
    } catch KeychainError.itemNotFound {
      let newKey = generateAPIKey()
      try saveAPIKey(newKey)
      return newKey
    }
  }
}

/// Creates a permissive SecAccess for legacy Keychain items so any application
/// running as the current user can access them without a password prompt.
/// This prevents repeated Keychain dialogs during Xcode debug rebuilds,
/// which produce a new ad-hoc code signature each time.
public enum KeychainAccess {
  public static func createPermissive(label: String) -> SecAccess? {
    var access: SecAccess?
    // Empty trusted-application list = any application can access without prompt
    let status = SecAccessCreate(label as CFString, [] as CFArray, &access)
    guard status == errSecSuccess else { return nil }
    return access
  }
}
