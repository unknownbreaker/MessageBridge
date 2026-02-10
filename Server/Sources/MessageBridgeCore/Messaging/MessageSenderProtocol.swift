import Foundation

/// Protocol for sending messages, enabling dependency injection and testing
public protocol MessageSenderProtocol: Sendable {
  /// Send a message to a recipient
  /// - Parameters:
  ///   - recipient: Phone number or email address
  ///   - text: Message content
  ///   - service: Optional service type ("iMessage" or "SMS"). If nil, defaults to iMessage.
  /// - Returns: Result indicating success or failure with details
  func sendMessage(to recipient: String, text: String, service: String?, replyToGuid: String?) async throws -> SendResult
}

/// Result of a send message operation
public struct SendResult: Codable, Sendable {
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
}

/// Errors that can occur when sending messages
public enum MessageSendError: Error, LocalizedError {
  case invalidRecipient(String)
  case emptyMessage
  case scriptExecutionFailed(String)
  case messagesAppNotAvailable

  public var errorDescription: String? {
    switch self {
    case .invalidRecipient(let recipient):
      return "Invalid recipient: \(recipient)"
    case .emptyMessage:
      return "Message text cannot be empty"
    case .scriptExecutionFailed(let reason):
      return "Failed to execute AppleScript: \(reason)"
    case .messagesAppNotAvailable:
      return "Messages.app is not available"
    }
  }
}
