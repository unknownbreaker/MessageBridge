import CryptoKit
import Foundation

/// End-to-end encryption using AES-GCM
/// Encrypts data so that relay servers (like Cloudflare) cannot read message content
public struct E2EEncryption: Sendable {
  private let key: SymmetricKey

  /// Initialize with an API key, deriving an encryption key using HKDF
  public init(apiKey: String) {
    // Derive a 256-bit encryption key from the API key using HKDF
    let apiKeyData = Data(apiKey.utf8)
    let salt = Data("MessageBridge-E2E-Salt-v1".utf8)
    let info = Data("MessageBridge-E2E-Encryption".utf8)

    // Use SHA256 of the API key as input key material
    let inputKeyMaterial = SHA256.hash(data: apiKeyData)
    let inputKey = SymmetricKey(data: Data(inputKeyMaterial))

    // Derive the final key using HKDF
    self.key = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: inputKey,
      salt: salt,
      info: info,
      outputByteCount: 32
    )
  }

  /// Encrypt data using AES-GCM
  /// Returns base64-encoded ciphertext with nonce prepended
  public func encrypt(_ data: Data) throws -> String {
    let nonce = AES.GCM.Nonce()
    let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

    // Combine nonce + ciphertext + tag
    guard let combined = sealedBox.combined else {
      throw E2EError.encryptionFailed
    }

    return combined.base64EncodedString()
  }

  /// Encrypt a string using AES-GCM
  public func encrypt(_ string: String) throws -> String {
    guard let data = string.data(using: .utf8) else {
      throw E2EError.invalidInput
    }
    return try encrypt(data)
  }

  /// Encrypt a Codable object to JSON then encrypt
  public func encrypt<T: Encodable>(_ object: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(object)
    return try encrypt(data)
  }

  /// Decrypt base64-encoded ciphertext
  public func decrypt(_ base64String: String) throws -> Data {
    guard let combined = Data(base64Encoded: base64String) else {
      throw E2EError.invalidBase64
    }

    let sealedBox = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(sealedBox, using: key)
  }

  /// Decrypt to a string
  public func decryptString(_ base64String: String) throws -> String {
    let data = try decrypt(base64String)
    guard let string = String(data: data, encoding: .utf8) else {
      throw E2EError.invalidUTF8
    }
    return string
  }

  /// Decrypt to a Codable object
  public func decrypt<T: Decodable>(_ base64String: String, as type: T.Type) throws -> T {
    let data = try decrypt(base64String)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
  }
}

/// Encrypted message envelope for API transport
public struct EncryptedEnvelope: Codable, Sendable {
  /// Version of the encryption scheme (for future compatibility)
  public let version: Int

  /// Base64-encoded encrypted payload
  public let payload: String

  public init(version: Int = 1, payload: String) {
    self.version = version
    self.payload = payload
  }
}

/// E2E encryption errors
public enum E2EError: LocalizedError {
  case encryptionFailed
  case decryptionFailed
  case invalidInput
  case invalidBase64
  case invalidUTF8
  case unsupportedVersion(Int)

  public var errorDescription: String? {
    switch self {
    case .encryptionFailed:
      return "Failed to encrypt data"
    case .decryptionFailed:
      return "Failed to decrypt data"
    case .invalidInput:
      return "Invalid input data"
    case .invalidBase64:
      return "Invalid base64 encoded string"
    case .invalidUTF8:
      return "Decrypted data is not valid UTF-8"
    case .unsupportedVersion(let version):
      return "Unsupported encryption version: \(version)"
    }
  }
}
