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
