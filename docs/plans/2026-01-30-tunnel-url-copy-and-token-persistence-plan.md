# Tunnel URL Copy & ngrok Token Persistence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a one-click "Copy Tunnel URL" button to the menu bar, and fix ngrok auth token persistence across Xcode rebuilds.

**Architecture:** Two independent changes. (1) Add a menu item to `MenuContentView` in `ServerApp.swift`. (2) In `NgrokManager.saveAuthToken`, write directly to the ngrok config file as fallback when the binary isn't found, so the token survives code-signing changes that invalidate Keychain.

**Tech Stack:** SwiftUI MenuBarExtra, macOS Keychain, file I/O

---

### Task 1: Add "Copy Tunnel URL" to Menu Bar

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeServer/App/ServerApp.swift:206-213`

**Step 1: Add the menu item**

In `MenuContentView`, after the existing "Copy API Key" button (line 211) and before the Divider (line 213), add a "Copy Tunnel URL" button that is only visible when a tunnel is running:

```swift
    Button("Copy API Key") {
      debugLog("Copy API Key clicked")
      appState.copyAPIKey()
    }

    if appState.tunnelStatus.isRunning {
      Button("Copy Tunnel URL") {
        debugLog("Copy Tunnel URL clicked")
        appState.copyTunnelURL()
      }
    }

    Divider()
```

**Step 2: Build and verify**

Run: `cd MessageBridgeServer && swift build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeServer/App/ServerApp.swift
git commit -m "feat(server): add Copy Tunnel URL to menu bar"
```

---

### Task 2: Fix ngrok auth token persistence — direct config file write

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Ngrok/NgrokManager.swift:560-584`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Tunnels/NgrokManagerTests.swift`

**Step 1: Write the failing test**

Add a test that verifies `saveAuthToken` writes to the config file even when the ngrok binary is not available. Create or add to `NgrokManagerTests.swift`:

```swift
import XCTest
@testable import MessageBridgeCore

final class NgrokAuthTokenPersistenceTests: XCTestCase {
    let testConfigDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ngrok-test-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: testConfigDir)
    }

    func testSaveAuthTokenWritesConfigFile() async throws {
        // Given: a known config path with no ngrok binary available
        let configPath = testConfigDir.appendingPathComponent("ngrok.yml")
        let manager = NgrokManager()

        // When: saving a token
        try await manager.saveAuthToken("test-token-123", configFilePath: configPath.path)

        // Then: the config file contains the token
        let contents = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(contents.contains("authtoken: test-token-123"))
    }

    func testSaveAuthTokenPreservesExistingConfig() async throws {
        // Given: an existing config file with other settings
        try FileManager.default.createDirectory(at: testConfigDir, withIntermediateDirectories: true)
        let configPath = testConfigDir.appendingPathComponent("ngrok.yml")
        try "version: \"2\"\nregion: us\n".write(toFile: configPath.path, atomically: true, encoding: .utf8)

        let manager = NgrokManager()

        // When: saving a token
        try await manager.saveAuthToken("new-token-456", configFilePath: configPath.path)

        // Then: the config file has the token AND preserves other settings
        let contents = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(contents.contains("authtoken: new-token-456"))
        XCTAssertTrue(contents.contains("version: \"2\""))
        XCTAssertTrue(contents.contains("region: us"))
    }

    func testSaveAuthTokenReplacesExistingToken() async throws {
        // Given: a config file with an old token
        try FileManager.default.createDirectory(at: testConfigDir, withIntermediateDirectories: true)
        let configPath = testConfigDir.appendingPathComponent("ngrok.yml")
        try "authtoken: old-token\nversion: \"2\"\n".write(toFile: configPath.path, atomically: true, encoding: .utf8)

        let manager = NgrokManager()

        // When: saving a new token
        try await manager.saveAuthToken("new-token-789", configFilePath: configPath.path)

        // Then: old token is replaced, not duplicated
        let contents = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(contents.contains("authtoken: new-token-789"))
        XCTAssertFalse(contents.contains("old-token"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter NgrokAuthTokenPersistenceTests`
Expected: FAIL — `saveAuthToken` doesn't accept a `configFilePath` parameter yet

**Step 3: Add direct config file write to `saveAuthToken`**

Modify `NgrokManager.saveAuthToken` (line 561) to accept an optional config file path and write directly when the binary isn't available:

```swift
  /// Save authtoken to Keychain, configure ngrok CLI, and write config file.
  public func saveAuthToken(_ token: String, configFilePath: String? = nil) async throws {
    // Save to Keychain
    try saveAuthTokenToKeychain(token)

    // Configure ngrok CLI if binary is available
    if let binaryPath = findBinary() {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: binaryPath)
      process.arguments = ["config", "add-authtoken", token]

      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe

      try process.run()
      process.waitUntilExit()

      if process.terminationStatus != 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TunnelError.connectionFailed("Failed to configure ngrok authtoken: \(output)")
      }
    } else {
      // No binary available — write directly to config file
      try writeAuthTokenToConfigFile(token, path: configFilePath)
    }
  }
```

Add the helper method after `saveAuthTokenToKeychain` (after line 674):

```swift
  /// Write authtoken directly to ngrok config file (fallback when binary unavailable).
  private nonisolated func writeAuthTokenToConfigFile(_ token: String, path: String? = nil) throws {
    let configPath: String
    if let path = path {
      configPath = path
    } else {
      // Use XDG path (~/.config/ngrok/ngrok.yml) as default
      configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ngrok/ngrok.yml").path
    }

    let configDir = (configPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(
      atPath: configDir, withIntermediateDirectories: true)

    if FileManager.default.fileExists(atPath: configPath),
       let existing = try? String(contentsOfFile: configPath, encoding: .utf8)
    {
      // Replace or append authtoken line
      var lines = existing.components(separatedBy: .newlines)
      if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("authtoken:") }) {
        lines[idx] = "authtoken: \(token)"
      } else {
        // Insert after first line (usually "version: ...") or at start
        lines.insert("authtoken: \(token)", at: lines.isEmpty ? 0 : 1)
      }
      // Remove trailing empty lines from join, then add final newline
      let content = lines.joined(separator: "\n")
        .trimmingCharacters(in: .newlines) + "\n"
      try content.write(toFile: configPath, atomically: true, encoding: .utf8)
    } else {
      // Create new config file
      let content = "version: \"2\"\nauthtoken: \(token)\n"
      try content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
  }
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeServer && swift test --filter NgrokAuthTokenPersistenceTests`
Expected: All 3 tests PASS

**Step 5: Run full test suite**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 6: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Ngrok/NgrokManager.swift
git add MessageBridgeServer/Tests/MessageBridgeCoreTests/Tunnels/NgrokAuthTokenPersistenceTests.swift
git commit -m "fix(server): write ngrok authtoken to config file when binary unavailable"
```

---

### Task 3: Add Keychain self-healing in detectAuthToken

**Files:**
- Modify: `MessageBridgeServer/Sources/MessageBridgeCore/Ngrok/NgrokManager.swift:536-558`
- Test: `MessageBridgeServer/Tests/MessageBridgeCoreTests/Tunnels/NgrokAuthTokenPersistenceTests.swift`

**Step 1: Write the failing test**

```swift
    func testDetectAuthTokenSelfHealsKeychain() throws {
        // Given: a config file with a token but Keychain is empty
        try FileManager.default.createDirectory(at: testConfigDir, withIntermediateDirectories: true)
        let configPath = testConfigDir.appendingPathComponent("ngrok.yml")
        try "authtoken: heal-me-123\n".write(toFile: configPath.path, atomically: true, encoding: .utf8)

        let manager = NgrokManager()

        // When: detecting the token with custom config path
        let token = manager.detectAuthToken(configPaths: [configPath.path])

        // Then: token is found from file
        XCTAssertEqual(token, "heal-me-123")
    }
```

**Step 2: Run test to verify it fails**

Run: `cd MessageBridgeServer && swift test --filter testDetectAuthTokenSelfHealsKeychain`
Expected: FAIL — `detectAuthToken` doesn't accept `configPaths`

**Step 3: Add configPaths parameter and self-healing**

Replace `detectAuthToken` (lines 536-558):

```swift
  /// Detect an existing authtoken from ngrok config files or Keychain.
  /// Checks modern config path first, then legacy, then Keychain.
  /// If found in config but not Keychain, re-saves to Keychain (self-healing).
  public nonisolated func detectAuthToken(configPaths: [String]? = nil) -> String? {
    let paths: [String]
    if let configPaths = configPaths {
      paths = configPaths
    } else {
      let macOSPath = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first?.appendingPathComponent("ngrok/ngrok.yml").path

      let xdgPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ngrok/ngrok.yml").path

      let legacyPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ngrok2/ngrok.yml").path

      paths = [macOSPath, xdgPath, legacyPath].compactMap { $0 }
    }

    for path in paths {
      if let token = parseAuthTokenFromConfig(at: path) {
        // Self-heal: if Keychain doesn't have it, re-save
        if retrieveAuthTokenFromKeychain() == nil {
          try? saveAuthTokenToKeychain(token)
        }
        return token
      }
    }

    return retrieveAuthTokenFromKeychain()
  }
```

**Step 4: Run tests**

Run: `cd MessageBridgeServer && swift test --filter NgrokAuthTokenPersistence`
Expected: All 4 tests PASS

**Step 5: Run full test suite**

Run: `cd MessageBridgeServer && swift test`
Expected: All tests pass

**Step 6: Commit**

```bash
git add MessageBridgeServer/Sources/MessageBridgeCore/Ngrok/NgrokManager.swift
git add MessageBridgeServer/Tests/MessageBridgeCoreTests/Tunnels/NgrokAuthTokenPersistenceTests.swift
git commit -m "fix(server): self-heal ngrok authtoken from config file to Keychain"
```

---

### Task 4: Final verification and update docs

**Step 1: Run full test suite for both projects**

Run: `cd MessageBridgeServer && swift test && cd ../MessageBridgeClient && swift test`
Expected: All tests pass

**Step 2: Update CLAUDE.md Current Focus**

Update the "Current Focus" section to reflect completed work.

**Step 3: Commit docs**

```bash
git add CLAUDE.md docs/plans/
git commit -m "docs: add tunnel URL copy and token persistence design and plan"
```
