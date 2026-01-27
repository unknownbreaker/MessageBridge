import XCTest

@testable import MessageBridgeClientCore

final class MessageEnrichmentTests: XCTestCase {
  func testMessage_defaultEnrichmentFields_areNil() {
    let message = Message(
      id: 1, guid: "g1", text: "Hello", date: Date(),
      isFromMe: true, handleId: nil, conversationId: "c1"
    )
    XCTAssertNil(message.detectedCodes)
    XCTAssertNil(message.highlights)
  }

  func testMessage_withDetectedCodes_storesValues() {
    let codes = [DetectedCode(value: "1234")]
    let message = Message(
      id: 1, guid: "g1", text: "Code: 1234", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      attachments: [],
      detectedCodes: codes
    )
    XCTAssertEqual(message.detectedCodes?.count, 1)
    XCTAssertEqual(message.detectedCodes?.first?.value, "1234")
  }

  func testMessage_withHighlights_storesValues() {
    let highlights = [TextHighlight(text: "https://example.com", type: .link)]
    let message = Message(
      id: 1, guid: "g1", text: "Visit https://example.com", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      attachments: [],
      detectedCodes: nil,
      highlights: highlights
    )
    XCTAssertEqual(message.highlights?.count, 1)
  }

  func testMessage_codable_roundTripsWithEnrichments() throws {
    let codes = [DetectedCode(value: "5678")]
    let highlights = [TextHighlight(text: "5678", type: .code)]
    let message = Message(
      id: 1, guid: "g1", text: "Code is 5678", date: Date(),
      isFromMe: false, handleId: 1, conversationId: "c1",
      attachments: [],
      detectedCodes: codes,
      highlights: highlights
    )
    let data = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(Message.self, from: data)
    XCTAssertEqual(decoded.detectedCodes, codes)
    XCTAssertEqual(decoded.highlights, highlights)
  }

  func testMessage_codable_decodesWithoutEnrichmentFields() throws {
    // Server may not send these fields — they should default to nil
    let json = """
      {
          "id": 1,
          "guid": "g1",
          "text": "Hello",
          "date": 0,
          "isFromMe": true,
          "conversationId": "c1",
          "attachments": []
      }
      """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let message = try decoder.decode(Message.self, from: json)
    XCTAssertNil(message.detectedCodes)
    XCTAssertNil(message.highlights)
  }
}
