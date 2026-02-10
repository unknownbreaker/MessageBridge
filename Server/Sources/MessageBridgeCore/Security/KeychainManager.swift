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

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]

    // Try to add the item
    var status = SecItemAdd(query as CFDictionary, nil)

    // If it already exists, update it
    if status == errSecDuplicateItem {
      let updateQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      let updateAttributes: [String: Any] = [
        kSecValueData as String: data
      ]
      status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
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
