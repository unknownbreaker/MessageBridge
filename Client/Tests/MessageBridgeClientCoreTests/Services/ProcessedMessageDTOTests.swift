import XCTest

@testable import MessageBridgeClientCore

final class ProcessedMessageDTOTests: XCTestCase {

  func testDecodesProcessedMessageWithEnrichments() throws {
    let json = """
      {
        "message": {
          "id": 42,
          "guid": "abc-123",
          "text": "Your code is 847293",
          "date": "2026-01-27T12:00:00Z",
          "isFromMe": false,
          "handleId": 1,
          "conversationId": "c1",
          "attachments": []
        },
        "detectedCodes": [{"value": "847293"}],
        "highlights": [{"text": "847293", "type": "code"}],
        "mentions": [],
        "isEmojiOnly": false
      }
      """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let dto = try decoder.decode(ProcessedMessageDTO.self, from: json)
    let message = dto.toMessage()

    XCTAssertEqual(message.id, 42)
    XCTAssertEqual(message.guid, "abc-123")
    XCTAssertEqual(message.text, "Your code is 847293")
    XCTAssertEqual(message.conversationId, "c1")
    XCTAssertFalse(message.isFromMe)
    XCTAssertEqual(message.detectedCodes?.count, 1)
    XCTAssertEqual(message.detectedCodes?.first?.value, "847293")
    XCTAssertEqual(message.highlights?.count, 1)
    XCTAssertEqual(message.highlights?.first?.type, .code)
    XCTAssertEqual(message.mentions?.count, 0)
  }

  func testDecodesWithoutOptionalEnrichments() throws {
    let json = """
      {
        "message": {
          "id": 1,
          "guid": "g1",
          "text": "Hello",
          "date": "2026-01-27T12:00:00Z",
          "isFromMe": true,
          "conversationId": "c1"
        }
      }
      """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let dto = try decoder.decode(ProcessedMessageDTO.self, from: json)
    let message = dto.toMessage()

    XCTAssertEqual(message.id, 1)
    XCTAssertEqual(message.text, "Hello")
    XCTAssertNil(message.detectedCodes)
    XCTAssertNil(message.highlights)
    XCTAssertNil(message.mentions)
  }

  func testDecodesWithMentions() throws {
    let json = """
      {
        "message": {
          "id": 5,
          "guid": "g5",
          "text": "Hey @john check this",
          "date": "2026-01-27T12:00:00Z",
          "isFromMe": false,
          "handleId": 2,
          "conversationId": "c2",
          "attachments": []
        },
        "detectedCodes": [],
        "highlights": [{"text": "@john", "type": "mention"}],
        "mentions": [{"text": "@john", "handle": "+15551234567"}],
        "isEmojiOnly": false
      }
      """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let dto = try decoder.decode(ProcessedMessageDTO.self, from: json)
    let message = dto.toMessage()

    XCTAssertEqual(message.mentions?.count, 1)
    XCTAssertEqual(message.mentions?.first?.text, "@john")
    XCTAssertEqual(message.mentions?.first?.handle, "+15551234567")
    XCTAssertEqual(message.highlights?.first?.type, .mention)
  }

  func testMessagesResponseDecodesArray() throws {
    let json = """
      {
        "messages": [
          {
            "message": {
              "id": 1,
              "guid": "g1",
              "text": "Hi",
              "date": "2026-01-27T12:00:00Z",
              "isFromMe": true,
              "conversationId": "c1"
            },
            "detectedCodes": [],
            "highlights": [],
            "mentions": [],
            "isEmojiOnly": false
          }
        ],
        "nextCursor": null
      }
      """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(MessagesResponse.self, from: json)
    XCTAssertEqual(response.messages.count, 1)
    let message = response.messages[0].toMessage()
    XCTAssertEqual(message.id, 1)
  }

  func testWebSocketNewMessageDecodesEnrichments() throws {
    let json = """
      {
        "type": "new_message",
        "data": {
          "message": {
            "message": {
              "id": 99,
              "guid": "ws-99",
              "text": "Code: 1234",
              "date": "2026-01-27T12:00:00Z",
              "isFromMe": false,
              "handleId": 1,
              "conversationId": "c1",
              "attachments": []
            },
            "detectedCodes": [{"value": "1234"}],
            "highlights": [{"text": "1234", "type": "code"}],
            "mentions": [],
            "isEmojiOnly": false
          }
        }
      }
      """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let wsMessage = try decoder.decode(NewMessageWebSocketMessage.self, from: json)
    let message = wsMessage.data.message.toMessage()

    XCTAssertEqual(message.id, 99)
    XCTAssertEqual(message.text, "Code: 1234")
    XCTAssertEqual(message.detectedCodes?.count, 1)
    XCTAssertEqual(message.detectedCodes?.first?.value, "1234")
  }
}
