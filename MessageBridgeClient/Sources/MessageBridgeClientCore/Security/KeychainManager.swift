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

/// Stored server configuration
public struct ServerConfig: Codable {
    public let serverURL: URL
    public let apiKey: String
    public let e2eEnabled: Bool

    public init(serverURL: URL, apiKey: String, e2eEnabled: Bool = false) {
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.e2eEnabled = e2eEnabled
    }

    // Custom decoder to handle missing e2eEnabled field in old configs
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(URL.self, forKey: .serverURL)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        e2eEnabled = try container.decodeIfPresent(Bool.self, forKey: .e2eEnabled) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case serverURL, apiKey, e2eEnabled
    }
}

/// Protocol for Keychain operations (for testability)
public protocol KeychainProtocol: Sendable {
    func saveServerConfig(_ config: ServerConfig) throws
    func retrieveServerConfig() throws -> ServerConfig
    func deleteServerConfig() throws
}

/// Manages secure storage of server configuration in the macOS Keychain
public struct KeychainManager: KeychainProtocol {
    private let service = "com.messagebridge.client"
    private let account = "server-config"

    public init() {}

    /// Save server configuration to the Keychain
    public func saveServerConfig(_ config: ServerConfig) throws {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(config) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Try to add the item
        var status = SecItemAdd(query as CFDictionary, nil)

        // If it already exists, update it
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
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

    /// Retrieve server configuration from the Keychain
    public func retrieveServerConfig() throws -> ServerConfig {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        let decoder = JSONDecoder()
        guard let config = try? decoder.decode(ServerConfig.self, from: data) else {
            throw KeychainError.invalidData
        }

        return config
    }

    /// Delete server configuration from the Keychain
    public func deleteServerConfig() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Check if server configuration exists
    public func hasServerConfig() -> Bool {
        do {
            _ = try retrieveServerConfig()
            return true
        } catch {
            return false
        }
    }
}
