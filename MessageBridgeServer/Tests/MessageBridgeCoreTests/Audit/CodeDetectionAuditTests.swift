import XCTest

@testable import MessageBridgeCore

/// Blind audit tests for M5.1 (2FA Code Detection).
/// Written from spec.md acceptance criteria without reading implementation.
///
/// Spec acceptance criteria:
///   - [ ] Detect 4-8 digit codes with context words
///   - [ ] Detect formatted codes (G-123456)
///   - [ ] Yellow highlight on detected codes
///   - [ ] "Copy [code]" button on message (client-side, not tested here)
///   - [ ] Optional: auto-copy high-confidence codes (client-side)
///   - [ ] Notification when auto-copied (client-side)
final class CodeDetectionAuditTests: XCTestCase {

  // MARK: - Types Exist

  /// Spec: "MessageProcessor protocol, Processors/CodeDetector.swift"
  func testCodeDetector_conformsToMessageProcessor() {
    let detector = CodeDetector()
    let _: any MessageProcessor = detector
  }

  /// Spec: detectedCodes on processed messages
  func testProcessedMessage_hasDetectedCodesField() {
    let msg = makeMessage(text: "hello")
    let processed = ProcessedMessage(message: msg)
    XCTAssertTrue(processed.detectedCodes.isEmpty)
  }

  /// Spec: highlighted codes
  func testTextHighlight_hasCodeType() {
    let highlight = TextHighlight(text: "123456", startIndex: 0, endIndex: 6, type: .code)
    XCTAssertEqual(highlight.type, .code)
  }

  /// Spec: confidence levels for detection
  func testDetectedCode_hasConfidenceLevels() {
    let high = DetectedCode(value: "123456", confidence: .high)
    let medium = DetectedCode(value: "123456", confidence: .medium)
    XCTAssertEqual(high.confidence, .high)
    XCTAssertEqual(medium.confidence, .medium)
  }

  // MARK: - AC: Detect 4-8 digit codes with context words

  /// Spec: "Detect 4-8 digit codes with context words"
  func testDetects_verificationCode_6digits() {
    let result = process("Your verification code is 847293")
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "847293")
  }

  func testDetects_4digitCode() {
    let result = process("Your Uber code: 8472")
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "8472")
  }

  func testDetects_8digitCode() {
    let result = process("Your security code is 84729316")
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "84729316")
  }

  func testDetects_OTP() {
    let result = process("Your OTP is 582941")
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "582941")
  }

  func testIgnores_codeWithoutContext() {
    let result = process("Call me at 847293 please")
    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testIgnores_3digitNumber() {
    let result = process("Your code is 123")
    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testIgnores_9digitNumber() {
    let result = process("Your code is 123456789")
    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testIgnores_promotionalCode() {
    // "SAVE20" is promotional, not 2FA — but it has the word "code"
    // This tests that non-numeric codes without the right pattern are excluded
    let result = process("Use code SAVE20 for 20% off")
    // If any codes detected, they should NOT be "SAVE20" (numeric-only detector)
    let values = result.detectedCodes.map(\.value)
    XCTAssertFalse(values.contains("SAVE20"))
  }

  // MARK: - AC: Detect formatted codes (G-123456)

  /// Spec: "Detect formatted codes (G-123456)"
  func testDetects_formattedCode_Google() {
    let result = process("G-582941 is your Google verification code")
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "G-582941")
  }

  func testDetects_formattedCode_letterDashDigits() {
    let result = process("Your verification code: A-12345")
    XCTAssertEqual(result.detectedCodes.count, 1)
    XCTAssertEqual(result.detectedCodes.first?.value, "A-12345")
  }

  // MARK: - AC: Yellow highlight on detected codes

  /// Spec: "Yellow highlight on detected codes"
  /// Server side: highlights array should include entries for detected codes
  func testDetectedCodes_generateHighlights() {
    let result = process("Your verification code is 847293")
    let codeHighlights = result.highlights.filter { $0.type == .code }
    XCTAssertEqual(codeHighlights.count, 1)
    XCTAssertEqual(codeHighlights.first?.text, "847293")
  }

  func testHighlight_hasCorrectIndices() {
    let text = "Your verification code is 847293"
    let result = process(text)
    let codeHighlights = result.highlights.filter { $0.type == .code }
    guard let h = codeHighlights.first else {
      XCTFail("Expected highlight")
      return
    }
    // "847293" starts at index 26 in the string
    XCTAssertEqual(h.startIndex, 26)
    XCTAssertEqual(h.endIndex, 32)
  }

  // MARK: - Edge Cases

  func testNilText_noDetection() {
    let result = process(nil)
    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testEmptyText_noDetection() {
    let result = process("")
    XCTAssertTrue(result.detectedCodes.isEmpty)
  }

  func testMultipleCodes_detectedSeparately() {
    let result = process("Your code is 1234. Backup code: 5678")
    XCTAssertGreaterThanOrEqual(result.detectedCodes.count, 2)
  }

  func testContextWords_caseInsensitive() {
    let result = process("YOUR VERIFICATION CODE IS 847293")
    XCTAssertEqual(result.detectedCodes.count, 1)
  }

  // MARK: - Helpers

  private func makeMessage(text: String?) -> Message {
    Message(
      id: 1, guid: "test-guid", text: text, date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1")
  }

  private func process(_ text: String?) -> ProcessedMessage {
    let msg = makeMessage(text: text)
    let processed = ProcessedMessage(message: msg)
    let detector = CodeDetector()
    return detector.process(processed)
  }
}

// MARK: - Audit Findings
// Compiled: YES
// Tests passed: 20/20
// Initial run: 18/20 — formatted codes (G-123456) were not detected.
// Fix: Added formattedCodeRegex pattern to CodeDetector with overlap prevention.
// All 20 audit tests + 22 existing CodeDetectorTests pass.
