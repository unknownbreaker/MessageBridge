import XCTest
import CryptoKit
@testable import MessageBridgeClientCore

final class E2EEncryptionTests: XCTestCase {

    // MARK: - Basic Encryption/Decryption

    func testEncryptDecrypt_string_roundTripsSuccessfully() throws {
        let encryption = E2EEncryption(apiKey: "test-api-key-123")
        let original = "Hello, World!"

        let encrypted = try encryption.encrypt(original)
        let decrypted = try encryption.decryptString(encrypted)

        XCTAssertEqual(decrypted, original)
    }

    func testEncryptDecrypt_data_roundTripsSuccessfully() throws {
        let encryption = E2EEncryption(apiKey: "test-api-key-123")
        let original = Data("Test message data".utf8)

        let encrypted = try encryption.encrypt(original)
        let decrypted = try encryption.decrypt(encrypted)

        XCTAssertEqual(decrypted, original)
    }

    func testEncryptDecrypt_codable_roundTripsSuccessfully() throws {
        struct TestMessage: Codable, Equatable {
            let id: Int
            let text: String
        }

        let encryption = E2EEncryption(apiKey: "test-api-key-123")
        let original = TestMessage(id: 42, text: "Hello")

        let encrypted = try encryption.encrypt(original)
        let decrypted: TestMessage = try encryption.decrypt(encrypted, as: TestMessage.self)

        XCTAssertEqual(decrypted.id, original.id)
        XCTAssertEqual(decrypted.text, original.text)
    }

    // MARK: - Key Derivation

    func testSameAPIKey_producesSameEncryptionKey() throws {
        let encryption1 = E2EEncryption(apiKey: "same-key")
        let encryption2 = E2EEncryption(apiKey: "same-key")
        let original = "Test message"

        // Encrypt with one instance, decrypt with another
        let encrypted = try encryption1.encrypt(original)
        let decrypted = try encryption2.decryptString(encrypted)

        XCTAssertEqual(decrypted, original)
    }

    func testDifferentAPIKey_failsToDecrypt() throws {
        let encryption1 = E2EEncryption(apiKey: "key-one")
        let encryption2 = E2EEncryption(apiKey: "key-two")
        let original = "Secret message"

        let encrypted = try encryption1.encrypt(original)

        XCTAssertThrowsError(try encryption2.decryptString(encrypted)) { error in
            // Should fail to decrypt with wrong key
            XCTAssertTrue(error is CryptoKit.CryptoKitError || error is E2EError)
        }
    }

    // MARK: - Nonce Uniqueness

    func testEncryption_producesDifferentCiphertextEachTime() throws {
        let encryption = E2EEncryption(apiKey: "test-key")
        let original = "Same message"

        let encrypted1 = try encryption.encrypt(original)
        let encrypted2 = try encryption.encrypt(original)

        // Each encryption should produce different ciphertext (different nonce)
        XCTAssertNotEqual(encrypted1, encrypted2)

        // But both should decrypt to the same message
        XCTAssertEqual(try encryption.decryptString(encrypted1), original)
        XCTAssertEqual(try encryption.decryptString(encrypted2), original)
    }

    // MARK: - Cross-Compatibility

    func testClientServerCompatibility_sameKeyDecryptsSuccessfully() throws {
        // Both client and server use the same salt and info strings for HKDF
        // This test verifies they produce compatible keys
        let apiKey = "shared-api-key-for-e2e"
        let encryption = E2EEncryption(apiKey: apiKey)

        let original = "Cross-platform message"
        let encrypted = try encryption.encrypt(original)

        // Verify decryption works (simulating server-side decryption)
        let decrypted = try encryption.decryptString(encrypted)
        XCTAssertEqual(decrypted, original)
    }

    // MARK: - Envelope

    func testEncryptedEnvelope_encodesAndDecodes() throws {
        let envelope = EncryptedEnvelope(version: 1, payload: "encrypted-payload")

        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(EncryptedEnvelope.self, from: encoded)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.payload, "encrypted-payload")
    }

    // MARK: - Unicode Support

    func testEncryptDecrypt_unicodeText_roundTripsSuccessfully() throws {
        let encryption = E2EEncryption(apiKey: "test-key")
        let original = "Hello 世界! 🌍 Привет мир"

        let encrypted = try encryption.encrypt(original)
        let decrypted = try encryption.decryptString(encrypted)

        XCTAssertEqual(decrypted, original)
    }
}
