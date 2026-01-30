import XCTest

@testable import MessageBridgeCore

final class NgrokAuthTokenPersistenceTests: XCTestCase {
  let testConfigDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("ngrok-test-\(UUID().uuidString)")

  override func tearDown() {
    try? FileManager.default.removeItem(at: testConfigDir)
  }

  func testSaveAuthTokenWritesConfigFile() async throws {
    let configPath = testConfigDir.appendingPathComponent("ngrok.yml")
    let manager = NgrokManager()
    try await manager.saveAuthToken("test-token-123", configFilePath: configPath.path)
    let contents = try String(contentsOfFile: configPath.path, encoding: .utf8)
    XCTAssertTrue(contents.contains("authtoken: test-token-123"))
  }

  func testSaveAuthTokenPreservesExistingConfig() async throws {
    try FileManager.default.createDirectory(at: testConfigDir, withIntermediateDirectories: true)
    let configPath = testConfigDir.appendingPathComponent("ngrok.yml")
    try "version: \"2\"\nregion: us\n".write(
      toFile: configPath.path, atomically: true, encoding: .utf8)
    let manager = NgrokManager()
    try await manager.saveAuthToken("new-token-456", configFilePath: configPath.path)
    let contents = try String(contentsOfFile: configPath.path, encoding: .utf8)
    XCTAssertTrue(contents.contains("authtoken: new-token-456"))
    XCTAssertTrue(contents.contains("version: \"2\""))
    XCTAssertTrue(contents.contains("region: us"))
  }

  func testSaveAuthTokenReplacesExistingToken() async throws {
    try FileManager.default.createDirectory(at: testConfigDir, withIntermediateDirectories: true)
    let configPath = testConfigDir.appendingPathComponent("ngrok.yml")
    try "authtoken: old-token\nversion: \"2\"\n".write(
      toFile: configPath.path, atomically: true, encoding: .utf8)
    let manager = NgrokManager()
    try await manager.saveAuthToken("new-token-789", configFilePath: configPath.path)
    let contents = try String(contentsOfFile: configPath.path, encoding: .utf8)
    XCTAssertTrue(contents.contains("authtoken: new-token-789"))
    XCTAssertFalse(contents.contains("old-token"))
  }

  func testDetectAuthTokenFindsTokenFromConfigFile() throws {
    // Given: a config file with a token
    try FileManager.default.createDirectory(at: testConfigDir, withIntermediateDirectories: true)
    let configPath = testConfigDir.appendingPathComponent("ngrok.yml")
    try "authtoken: found-me-123\n".write(
      toFile: configPath.path, atomically: true, encoding: .utf8)

    let manager = NgrokManager()

    // When: detecting with custom config path
    let token = manager.detectAuthToken(configPaths: [configPath.path])

    // Then: token is found
    XCTAssertEqual(token, "found-me-123")
  }
}
