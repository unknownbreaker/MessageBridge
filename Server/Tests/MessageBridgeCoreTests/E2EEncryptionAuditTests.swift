import XCTest

@testable import MessageBridgeCore

/// Blind spec-based audit tests for M2.4 E2E Encryption.
///
/// Written from spec.md acceptance criteria:
/// - AES-256-GCM encryption
/// - Key derived from API key via HKDF
/// - Required for Cloudflare/ngrok, optional for Tailscale
final class E2EEncryptionAuditTests: XCTestCase {

  // MARK: - Roundtrip (M2.4: "AES-256-GCM encryption")

  func testRoundtripEncryptDecryptString() throws {
    let e2e = E2EEncryption(apiKey: "test-api-key-12345")
    let original = "Hello, secure world!"
    let encrypted = try e2e.encrypt(original)
    let decrypted = try e2e.decryptString(encrypted)
    XCTAssertEqual(decrypted, original)
  }

  func testRoundtripEncryptDecryptData() throws {
    let e2e = E2EEncryption(apiKey: "test-api-key-12345")
    let original = Data("binary data here".utf8)
    let encrypted = try e2e.encrypt(original)
    let decrypted = try e2e.decrypt(encrypted)
    XCTAssertEqual(decrypted, original)
  }

  func testRoundtripEncryptDecryptCodable() throws {
    struct TestPayload: Codable, Equatable {
      let name: String
      let count: Int
    }
    let e2e = E2EEncryption(apiKey: "test-key")
    let original = TestPayload(name: "test", count: 42)
    let encrypted = try e2e.encrypt(original)
    let decrypted = try e2e.decrypt(encrypted, as: TestPayload.self)
    XCTAssertEqual(decrypted, original)
  }

  func testRoundtripUnicode() throws {
    let e2e = E2EEncryption(apiKey: "test-key")
    let original = "Hello! Привет! こんにちは! 🌍"
    let encrypted = try e2e.encrypt(original)
    let decrypted = try e2e.decryptString(encrypted)
    XCTAssertEqual(decrypted, original)
  }

  // MARK: - HKDF Key Derivation (M2.4: "Key derived from API key via HKDF")

  func testHKDFKeyDerivation_sameKeyProducesConsistentResults() throws {
    let e2e1 = E2EEncryption(apiKey: "same-key")
    let e2e2 = E2EEncryption(apiKey: "same-key")
    let plaintext = "test message"
    let encrypted = try e2e1.encrypt(plaintext)
    let decrypted = try e2e2.decryptString(encrypted)
    XCTAssertEqual(decrypted, plaintext)
  }

  func testHKDFKeyDerivation_differentKeysCantCrossDecrypt() throws {
    let e2e1 = E2EEncryption(apiKey: "key-one")
    let e2e2 = E2EEncryption(apiKey: "key-two")
    let encrypted = try e2e1.encrypt("secret")
    XCTAssertThrowsError(try e2e2.decryptString(encrypted))
  }

  // MARK: - Nonce Uniqueness

  func testNonceUniqueness() throws {
    let e2e = E2EEncryption(apiKey: "test-key")
    let plaintext = "same text"
    let encrypted1 = try e2e.encrypt(plaintext)
    let encrypted2 = try e2e.encrypt(plaintext)
    XCTAssertNotEqual(encrypted1, encrypted2)
  }

  // MARK: - Encrypted Envelope Format

  func testEncryptedEnvelopeFormat() throws {
    let envelope = EncryptedEnvelope(version: 1, payload: "base64data")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(EncryptedEnvelope.self, from: data)
    XCTAssertEqual(decoded.version, 1)
    XCTAssertEqual(decoded.payload, "base64data")
  }

  func testEncryptedEnvelope_defaultVersion() {
    let envelope = EncryptedEnvelope(payload: "data")
    XCTAssertEqual(envelope.version, 1)
  }

  // MARK: - Error Handling

  func testInvalidBase64_throws() {
    let e2e = E2EEncryption(apiKey: "test-key")
    XCTAssertThrowsError(try e2e.decrypt("not-valid-base64!!!"))
  }

  func testTruncatedData_throws() {
    let e2e = E2EEncryption(apiKey: "test-key")
    // Valid base64 but too short to be valid AES-GCM ciphertext
    XCTAssertThrowsError(try e2e.decrypt("aGVsbG8="))
  }

  // MARK: - Error Types

  func testE2EError_hasDescriptions() {
    let errors: [E2EError] = [
      .encryptionFailed, .decryptionFailed, .invalidInput,
      .invalidBase64, .invalidUTF8, .unsupportedVersion(99),
    ]
    for error in errors {
      XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
    }
  }
}
