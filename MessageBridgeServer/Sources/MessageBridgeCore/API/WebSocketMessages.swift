import Vapor

/// WebSocket message types sent from server to client
public enum WebSocketMessageType: String, Codable, Sendable {
  case newMessage = "new_message"
  case connected = "connected"
  case error = "error"
  case tapbackAdded = "tapback_added"
  case tapbackRemoved = "tapback_removed"
  case syncWarning = "sync_warning"
  case syncWarningCleared = "sync_warning_cleared"
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

  /// The tapback type raw value (2000-2006).
  public let tapbackType: Int

  /// The handle ID of the sender (e.g., "+15551234567" or "email@example.com").
  public let sender: String

  /// Whether this tapback was sent by the current user.
  public let isFromMe: Bool

  /// The conversation ID for the client to find the message.
  public let conversationId: String

  /// The custom emoji for `.customEmoji` type tapbacks (iOS 17+). Nil for classic types.
  public let emoji: String?

  public init(
    messageGUID: String,
    tapbackType: TapbackType,
    sender: String,
    isFromMe: Bool,
    conversationId: String,
    emoji: String? = nil
  ) {
    self.messageGUID = messageGUID
    self.tapbackType = tapbackType.rawValue
    self.sender = sender
    self.isFromMe = isFromMe
    self.conversationId = conversationId
    self.emoji = emoji
  }

}

/// Data payload for sync warning events
public struct SyncWarningEvent: Codable, Sendable {
  public let conversationId: String
  public let message: String

  public init(conversationId: String, message: String) {
    self.conversationId = conversationId
    self.message = message
  }
}

/// Data payload for sync warning cleared events
public struct SyncWarningClearedEvent: Codable, Sendable {
  public let conversationId: String

  public init(conversationId: String) {
    self.conversationId = conversationId
  }
}
