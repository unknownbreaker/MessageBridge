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
    public let messages: [Message]
    public let nextCursor: String?

    public init(messages: [Message], nextCursor: String? = nil) {
        self.messages = messages
        self.nextCursor = nextCursor
    }
}

/// Response for GET /search
public struct SearchResponse: Content {
    public let messages: [Message]
    public let query: String

    public init(messages: [Message], query: String) {
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
