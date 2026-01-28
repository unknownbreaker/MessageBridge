# Phase 2 Milestone Audit — Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Audit Phase 2 milestones (M2.1 Tailscale, M2.2 Cloudflare, M2.4 E2E Encryption) by writing blind spec-based tests. M2.3 ngrok is deferred (not yet implemented).

**Approach:** Write tests from spec.md acceptance criteria without reading implementation code. Compilation failures and test failures are both valid audit findings. Tests verify logic/parsing only — no CLI tools required.

**Tech Stack:** Swift, XCTest

---

### Task 1: M2.1 Tailscale Audit Tests

**Files:**
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/TailscaleAuditTests.swift`

**Step 1: Write tests**

```swift
import XCTest
@testable import MessageBridgeCore

final class TailscaleAuditTests: XCTestCase {
  // M2.1 Spec: "Auto-detect Tailscale IP address"
  // M2.1 Spec: "Status indicator in menu bar"
  // M2.1 Spec: "Can set as default tunnel"

  func testConformsToTunnelProvider() {
    // TailscaleManager should conform to TunnelProvider protocol
    let manager = TailscaleManager()
    XCTAssertTrue(manager is TunnelProvider)
  }

  func testHasExpectedIdentity() {
    let manager = TailscaleManager()
    XCTAssertEqual(manager.id, "tailscale")
    XCTAssertFalse(manager.displayName.isEmpty)
  }

  func testStatusType_coversExpectedStates() {
    // Spec requires status indicator — verify status enum exists
    // with at least: not installed, stopped, connecting, connected, error
    let notInstalled = TailscaleStatus.notInstalled
    let stopped = TailscaleStatus.stopped
    let connecting = TailscaleStatus.connecting
    let connected = TailscaleStatus.connected(ip: "100.64.0.1", hostname: "mac")
    let error = TailscaleStatus.error("fail")

    // Each should be distinguishable
    XCTAssertNotEqual(notInstalled, stopped)
    XCTAssertNotEqual(stopped, connecting)
    _ = connected // Just verify it compiles with associated values
    _ = error
  }

  func testStatusConversion_toTunnelStatus() async {
    // TunnelProvider protocol uses TunnelStatus — verify conversion works
    let manager = TailscaleManager()
    let status = await manager.status
    // Should return a valid TunnelStatus (not crash)
    _ = status
  }
}
```

**Step 2: Run tests, record results**

Run: `cd MessageBridgeServer && swift test --filter TailscaleAuditTests 2>&1 | tail -10`

**Step 3: Document findings**

Record which tests pass, fail, or don't compile. Each is a valid audit finding.

**Step 4: Commit**

```bash
git add MessageBridgeServer/Tests/MessageBridgeCoreTests/TailscaleAuditTests.swift
git commit -m "test(audit): add M2.1 Tailscale audit tests"
```

---

### Task 2: M2.2 Cloudflare Audit Tests

**Files:**
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/CloudflareAuditTests.swift`

**Step 1: Write tests**

```swift
import XCTest
@testable import MessageBridgeCore

final class CloudflareAuditTests: XCTestCase {
  // M2.2 Spec: "Manages cloudflared process"
  // M2.2 Spec: "Setup wizard for first-time configuration"
  // M2.2 Spec: "Can set as default tunnel"

  func testConformsToTunnelProvider() {
    let manager = CloudflaredManager()
    XCTAssertTrue(manager is TunnelProvider)
  }

  func testHasExpectedIdentity() {
    let manager = CloudflaredManager()
    XCTAssertEqual(manager.id, "cloudflare")
    XCTAssertFalse(manager.displayName.isEmpty)
  }

  func testStatusType_coversExpectedStates() {
    // Spec requires managing process — verify status covers lifecycle
    let stopped = CloudflaredManager.TunnelStatus.stopped
    let notInstalled = CloudflaredManager.TunnelStatus.notInstalled
    let starting = CloudflaredManager.TunnelStatus.starting
    let running = CloudflaredManager.TunnelStatus.running(url: "https://test.trycloudflare.com")
    let error = CloudflaredManager.TunnelStatus.error("fail")

    XCTAssertNotEqual(stopped, notInstalled)
    _ = starting
    _ = running
    _ = error
  }

  func testStatusDisplayText_allStatesHaveText() {
    // UI requires human-readable status
    let states: [CloudflaredManager.TunnelStatus] = [
      .stopped, .notInstalled, .starting,
      .running(url: "https://test.trycloudflare.com"),
      .error("test")
    ]
    for state in states {
      XCTAssertFalse(state.displayText.isEmpty, "Status \(state) should have display text")
    }
  }

  func testInitialStatus_isStopped() async {
    let manager = CloudflaredManager()
    let status = await manager.tunnelStatus
    XCTAssertEqual(status, .stopped)
  }
}
```

**Step 2: Run tests, record results**

Run: `cd MessageBridgeServer && swift test --filter CloudflareAuditTests 2>&1 | tail -10`

**Step 3: Document findings**

**Step 4: Commit**

```bash
git add MessageBridgeServer/Tests/MessageBridgeCoreTests/CloudflareAuditTests.swift
git commit -m "test(audit): add M2.2 Cloudflare audit tests"
```

---

### Task 3: M2.4 E2E Encryption Audit Tests

**Files:**
- Create: `MessageBridgeServer/Tests/MessageBridgeCoreTests/E2EEncryptionAuditTests.swift`

**Step 1: Write tests**

```swift
import XCTest
@testable import MessageBridgeCore

final class E2EEncryptionAuditTests: XCTestCase {
  // M2.4 Spec: "AES-256-GCM encryption"
  // M2.4 Spec: "Key derived from API key via HKDF"
  // M2.4 Spec: "Required for Cloudflare/ngrok, optional for Tailscale"

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

  func testHKDFKeyDerivation_sameKeyProducesConsistentResults() throws {
    let e2e1 = E2EEncryption(apiKey: "same-key")
    let e2e2 = E2EEncryption(apiKey: "same-key")
    let plaintext = "test message"
    let encrypted = try e2e1.encrypt(plaintext)
    // Second instance with same key should decrypt
    let decrypted = try e2e2.decryptString(encrypted)
    XCTAssertEqual(decrypted, plaintext)
  }

  func testHKDFKeyDerivation_differentKeysCantCrossDecrypt() throws {
    let e2e1 = E2EEncryption(apiKey: "key-one")
    let e2e2 = E2EEncryption(apiKey: "key-two")
    let encrypted = try e2e1.encrypt("secret")
    XCTAssertThrowsError(try e2e2.decryptString(encrypted))
  }

  func testNonceUniqueness() throws {
    let e2e = E2EEncryption(apiKey: "test-key")
    let plaintext = "same text"
    let encrypted1 = try e2e.encrypt(plaintext)
    let encrypted2 = try e2e.encrypt(plaintext)
    // Same plaintext should produce different ciphertext (random nonce)
    XCTAssertNotEqual(encrypted1, encrypted2)
  }

  func testEncryptedEnvelopeFormat() throws {
    // Spec implies a wire format for transport
    let envelope = EncryptedEnvelope(version: 1, payload: "base64data")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(EncryptedEnvelope.self, from: data)
    XCTAssertEqual(decoded.version, 1)
    XCTAssertEqual(decoded.payload, "base64data")
  }

  func testInvalidInputHandling() {
    let e2e = E2EEncryption(apiKey: "test-key")
    // Invalid base64 should throw
    XCTAssertThrowsError(try e2e.decrypt("not-valid-base64!!!"))
    // Truncated data should throw
    XCTAssertThrowsError(try e2e.decrypt("aGVsbG8="))
  }
}
```

**Step 2: Run tests, record results**

Run: `cd MessageBridgeServer && swift test --filter E2EEncryptionAuditTests 2>&1 | tail -10`

**Step 3: Document findings**

**Step 4: Commit**

```bash
git add MessageBridgeServer/Tests/MessageBridgeCoreTests/E2EEncryptionAuditTests.swift
git commit -m "test(audit): add M2.4 E2E Encryption audit tests"
```

---

### Task 4: Update Audit Tracker

**Files:**
- Modify: `CLAUDE.md` — Update Phase 2 rows in Milestone Audit Tracker

**Step 1: Update tracker**

Set "Spec Tests Written" to checkmark for M2.1, M2.2, M2.4. Record "Tests Pass" based on actual results. Mark M2.3 as deferred.

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update Phase 2 audit tracker with results"
```
