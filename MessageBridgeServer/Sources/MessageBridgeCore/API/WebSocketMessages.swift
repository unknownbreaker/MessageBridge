import Vapor

/// WebSocket message types sent from server to client
public enum WebSocketMessageType: String, Codable, Sendable {
  case newMessage = "new_message"
  case connected = "connected"
  case error = "error"
  case tapbackAdded = "tapback_added"
  case tapbackRemoved = "tapback_removed"
}

/// Base WebSocket message envelope
public struct WebSocketMessage<T: Codable & Sendable>: Codable, Sendable {
  public let type: WebSocketMessageType
  public let data: T

  public init(type: WebSocketMessageType, data: T) {
    self.type = type
    self.data = data
  }
}

/// Data payload for new message notifications
public struct NewMessageData: Codable, Sendable {
  public let message: ProcessedMessage

  public init(message: ProcessedMessage) {
    self.message = message
  }

  public init(from message: ProcessedMessage) {
    self.message = message
  }
}

/// Data payload for connection confirmation
public struct ConnectedData: Codable, Sendable {
  public let message: String

  public init(message: String = "Connected to MessageBridge") {
    self.message = message
  }
}

/// Data payload for error messages
public struct ErrorData: Codable, Sendable {
  public let message: String

  public init(message: String) {
    self.message = message
  }
}

/// Data payload for tapback events (added or removed)
public struct TapbackEvent: Codable, Sendable {
  /// The GUID of the message this tapback is attached to.
  public let messageGUID: String

  /// The tapback type as a string (e.g., "love", "like", "dislike", "laugh", "emphasis", "question").
  public let tapbackType: String

  /// The handle ID of the sender (e.g., "+15551234567" or "email@example.com").
  public let sender: String

  /// Whether this tapback was sent by the current user.
  public let isFromMe: Bool

  /// The conversation ID for the client to find the message.
  public let conversationId: String

  public init(
    messageGUID: String,
    tapbackType: TapbackType,
    sender: String,
    isFromMe: Bool,
    conversationId: String
  ) {
    self.messageGUID = messageGUID
    self.tapbackType = String(describing: tapbackType)
    self.sender = sender
    self.isFromMe = isFromMe
    self.conversationId = conversationId
  }

  /// Alternative initializer accepting tapbackType as a raw string.
  public init(
    messageGUID: String,
    tapbackType: String,
    sender: String,
    isFromMe: Bool,
    conversationId: String
  ) {
    self.messageGUID = messageGUID
    self.tapbackType = tapbackType
    self.sender = sender
    self.isFromMe = isFromMe
    self.conversationId = conversationId
  }
}
