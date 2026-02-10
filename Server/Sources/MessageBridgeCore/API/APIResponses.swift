import Vapor

/// Response for GET /health
public struct HealthResponse: Content {
  public let status: String
  public let timestamp: Date

  public init(status: String = "ok", timestamp: Date = Date()) {
    self.status = status
    self.timestamp = timestamp
  }
}

/// Response for GET /conversations
public struct ConversationsResponse: Content {
  public let conversations: [Conversation]
  public let nextCursor: String?

  public init(conversations: [Conversation], nextCursor: String? = nil) {
    self.conversations = conversations
    self.nextCursor = nextCursor
  }
}

/// Response for GET /conversations/:id/messages
public struct MessagesResponse: Content {
  public let messages: [ProcessedMessage]
  public let nextCursor: String?

  public init(messages: [ProcessedMessage], nextCursor: String? = nil) {
    self.messages = messages
    self.nextCursor = nextCursor
  }
}

/// Response for GET /search
public struct SearchResponse: Content {
  public let messages: [ProcessedMessage]
  public let query: String

  public init(messages: [ProcessedMessage], query: String) {
    self.messages = messages
    self.query = query
  }
}

/// Error response format
public struct ErrorResponse: Content {
  public let error: Bool
  public let reason: String

  public init(reason: String) {
    self.error = true
    self.reason = reason
  }
}

/// Request body for POST /send
public struct SendMessageRequest: Content {
  public let to: String
  public let text: String
  public let service: String?

  public init(to: String, text: String, service: String? = nil) {
    self.to = to
    self.text = text
    self.service = service
  }
}

/// Response for POST /send
public struct SendResponse: Content {
  public let success: Bool
  public let recipient: String
  public let service: String
  public let timestamp: Date

  public init(success: Bool, recipient: String, service: String, timestamp: Date = Date()) {
    self.success = success
    self.recipient = recipient
    self.service = service
    self.timestamp = timestamp
  }

  public init(from result: SendResult) {
    self.success = result.success
    self.recipient = result.recipient
    self.service = result.service
    self.timestamp = result.timestamp
  }
}

/// Request body for POST /messages/:id/tapback
public struct TapbackRequest: Content {
  /// The tapback type: love, like, dislike, laugh, emphasis, question
  public let type: String
  /// The action: "add" or "remove"
  public let action: String

  public init(type: String, action: String) {
    self.type = type
    self.action = action
  }
}

/// Response for POST /messages/:id/tapback
public struct TapbackResponse: Content {
  public let success: Bool
  public let error: String?
  public let messageGUID: String?
  public let tapbackType: String?
  public let action: String?

  public init(
    success: Bool, error: String? = nil, messageGUID: String? = nil, tapbackType: String? = nil,
    action: String? = nil
  ) {
    self.success = success
    self.error = error
    self.messageGUID = messageGUID
    self.tapbackType = tapbackType
    self.action = action
  }
}
