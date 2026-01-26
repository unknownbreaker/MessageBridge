import Vapor

/// WebSocket message types sent from server to client
public enum WebSocketMessageType: String, Codable, Sendable {
  case newMessage = "new_message"
  case connected = "connected"
  case error = "error"
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
  public let id: Int64
  public let conversationId: String
  public let text: String?
  public let sender: String?
  public let date: Date
  public let isFromMe: Bool

  public init(
    id: Int64, conversationId: String, text: String?, sender: String?, date: Date, isFromMe: Bool
  ) {
    self.id = id
    self.conversationId = conversationId
    self.text = text
    self.sender = sender
    self.date = date
    self.isFromMe = isFromMe
  }

  public init(from message: Message, sender: String?) {
    self.id = message.id
    self.conversationId = message.conversationId
    self.text = message.text
    self.sender = sender
    self.date = message.date
    self.isFromMe = message.isFromMe
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
