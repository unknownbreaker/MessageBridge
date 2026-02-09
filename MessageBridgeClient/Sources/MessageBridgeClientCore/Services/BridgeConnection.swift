import Foundation

/// Callback for receiving new messages via WebSocket
public typealias NewMessageHandler = @Sendable (Message, String) -> Void

/// Callback for receiving tapback events via WebSocket
public typealias TapbackEventHandler = @Sendable (TapbackEvent) -> Void

/// Callback for receiving sync warning events via WebSocket
public typealias SyncWarningHandler = @Sendable (SyncWarningEvent) -> Void

/// Callback for receiving sync warning cleared events via WebSocket
public typealias SyncWarningClearedHandler = @Sendable (SyncWarningClearedEvent) -> Void

/// Callback for receiving pinned conversations changed events via WebSocket
public typealias PinnedConversationsChangedHandler =
  @Sendable (PinnedConversationsChangedEvent) -> Void

/// Action type for tapback operations
public enum TapbackActionType: String, Sendable {
  case add
  case remove
}

/// WebSocket event for tapback added/removed
public struct TapbackEvent: Codable, Sendable {
  public let messageGUID: String
  public let tapbackType: TapbackType
  public let sender: String
  public let isFromMe: Bool
  public let conversationId: String
  public let isRemoval: Bool
  public let emoji: String?

  public init(
    messageGUID: String,
    tapbackType: TapbackType,
    sender: String,
    isFromMe: Bool,
    conversationId: String,
    isRemoval: Bool,
    emoji: String? = nil
  ) {
    self.messageGUID = messageGUID
    self.tapbackType = tapbackType
    self.sender = sender
    self.isFromMe = isFromMe
    self.conversationId = conversationId
    self.isRemoval = isRemoval
    self.emoji = emoji
  }
}

/// Entry in the pinned conversations changed event
public struct PinnedConversationEntry: Codable, Sendable {
  public let conversationId: String
  public let index: Int
}

/// Event received when Messages.app pin state changes
public struct PinnedConversationsChangedEvent: Codable, Sendable {
  public let pinned: [PinnedConversationEntry]
}

/// Protocol defining the bridge service interface for testability
public protocol BridgeServiceProtocol: Sendable {
  func connect(to url: URL, apiKey: String, e2eEnabled: Bool) async throws
  func disconnect() async
  func fetchConversations(limit: Int, offset: Int) async throws -> [Conversation]
  func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message]
  func sendMessage(text: String, to recipient: String) async throws
  func startWebSocket(
    onNewMessage: @escaping NewMessageHandler,
    onTapbackEvent: @escaping TapbackEventHandler,
    onSyncWarning: @escaping SyncWarningHandler,
    onSyncWarningCleared: @escaping SyncWarningClearedHandler,
    onPinnedConversationsChanged: @escaping PinnedConversationsChangedHandler
  ) async throws
  func stopWebSocket() async
  func fetchAttachment(id: Int64) async throws -> Data
  func markConversationAsRead(_ conversationId: String) async throws
  func sendTapback(type: TapbackType, messageGUID: String, action: TapbackActionType) async throws
}

/// Response wrapper for conversations endpoint
struct ConversationsResponse: Codable {
  let conversations: [Conversation]
  let nextCursor: String?
}

/// Server's ProcessedMessage DTO — matches the nested JSON structure.
/// Converts to client `Message` with enrichment fields populated.
struct ProcessedMessageDTO: Codable {
  let message: RawMessageDTO
  let detectedCodes: [DetectedCode]?
  let highlights: [TextHighlight]?
  let mentions: [Mention]?
  let isEmojiOnly: Bool?
  let tapbacks: [Tapback]?

  /// Flattened raw message fields from the server's Message type
  struct RawMessageDTO: Codable {
    let id: Int64
    let guid: String
    let text: String?
    let date: Date
    let isFromMe: Bool
    let handleId: Int64?
    let conversationId: String
    let attachments: [Attachment]?
    let dateDelivered: Date?
    let dateRead: Date?
    let linkPreview: LinkPreview?
  }

  func toMessage() -> Message {
    Message(
      id: message.id,
      guid: message.guid,
      text: message.text,
      date: message.date,
      isFromMe: message.isFromMe,
      handleId: message.handleId,
      conversationId: message.conversationId,
      attachments: message.attachments ?? [],
      detectedCodes: detectedCodes,
      highlights: highlights,
      mentions: mentions,
      tapbacks: tapbacks,
      dateDelivered: message.dateDelivered,
      dateRead: message.dateRead,
      linkPreview: message.linkPreview
    )
  }
}

/// Response wrapper for messages endpoint
struct MessagesResponse: Codable {
  let messages: [ProcessedMessageDTO]
  let nextCursor: String?
}

/// Response from POST /send endpoint
struct SendResponse: Codable {
  let success: Bool
  let recipient: String
  let service: String
  let timestamp: Date
}

/// WebSocket message envelope - decode type first, then data based on type
struct WebSocketEnvelope: Codable {
  let type: String
}

/// Full new_message WebSocket message
struct NewMessageWebSocketMessage: Codable {
  let type: String
  let data: NewMessagePayload
}

/// Data payload for new_message type — wraps a ProcessedMessage
struct NewMessagePayload: Codable {
  let message: ProcessedMessageDTO
}

/// WebSocket message for tapback events
struct TapbackWebSocketMessage: Codable {
  let type: String
  let data: TapbackEventPayload
}

/// Data payload for tapback_added/tapback_removed WebSocket events
struct TapbackEventPayload: Codable {
  let messageGUID: String
  let tapbackType: Int
  let sender: String
  let isFromMe: Bool
  let conversationId: String
  let emoji: String?
}

/// WebSocket message for sync warning events
struct SyncWarningWebSocketMessage: Codable {
  let type: String
  let data: SyncWarningEvent
}

/// WebSocket message for sync warning cleared events
struct SyncWarningClearedWebSocketMessage: Codable {
  let type: String
  let data: SyncWarningClearedEvent
}

/// WebSocket message for pinned conversations changed events
struct PinnedConversationsWebSocketMessage: Codable {
  let type: String
  let data: PinnedConversationsChangedEvent
}

/// Handles communication with the MessageBridge server
public actor BridgeConnection: BridgeServiceProtocol {
  private var serverURL: URL?
  private var apiKey: String?
  private var urlSession: URLSession
  private var webSocketTask: URLSessionWebSocketTask?
  private var newMessageHandler: NewMessageHandler?
  private var tapbackEventHandler: TapbackEventHandler?
  private var syncWarningHandler: SyncWarningHandler?
  private var syncWarningClearedHandler: SyncWarningClearedHandler?
  private var pinnedConversationsChangedHandler: PinnedConversationsChangedHandler?
  private var e2eEnabled: Bool = false
  private var encryption: E2EEncryption?

  public init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    self.urlSession = URLSession(configuration: config)
  }

  public func disconnect() async {
    await stopWebSocket()
    serverURL = nil
    apiKey = nil
    e2eEnabled = false
    encryption = nil
    logDebug("Disconnected from server")
  }

  public func connect(to url: URL, apiKey: String, e2eEnabled: Bool = false) async throws {
    self.serverURL = url
    self.apiKey = apiKey
    self.e2eEnabled = e2eEnabled

    // Initialize encryption if E2E is enabled
    if e2eEnabled {
      self.encryption = E2EEncryption(apiKey: apiKey)
    }

    // Test connection with health check
    let healthURL = url.appendingPathComponent("health")
    var request = URLRequest(url: healthURL)
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")

    logDebug("Attempting to connect to: \(healthURL.absoluteString)")

    do {
      let (data, response) = try await urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        logError("Connection failed: Response is not HTTP")
        throw BridgeError.connectionFailed
      }

      logDebug("Server responded with status: \(httpResponse.statusCode)")

      if httpResponse.statusCode != 200 {
        let body = String(data: data, encoding: .utf8) ?? "empty"
        logError("Connection failed: HTTP \(httpResponse.statusCode) - \(body)")
        throw BridgeError.connectionFailed
      }

      logInfo("Successfully connected to server")
    } catch let error as BridgeError {
      throw error
    } catch {
      logError("Connection failed: \(error.localizedDescription)")
      throw BridgeError.connectionFailed
    }
  }

  public func fetchConversations(limit: Int = 50, offset: Int = 0) async throws -> [Conversation] {
    guard let serverURL, let apiKey else {
      throw BridgeError.notConnected
    }

    var components = URLComponents(
      url: serverURL.appendingPathComponent("conversations"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "offset", value: String(offset)),
    ]

    var request = URLRequest(url: components.url!)
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    if e2eEnabled {
      request.addValue("enabled", forHTTPHeaderField: "X-E2E-Encryption")
    }

    let (data, httpResponse) = try await urlSession.data(for: request)

    guard let response = httpResponse as? HTTPURLResponse,
      response.statusCode == 200
    else {
      throw BridgeError.requestFailed
    }

    let conversationsResponse = try decryptResponse(data, as: ConversationsResponse.self)
    return conversationsResponse.conversations
  }

  public func fetchMessages(conversationId: String, limit: Int = 50, offset: Int = 0) async throws
    -> [Message]
  {
    guard let serverURL, let apiKey else {
      throw BridgeError.notConnected
    }

    // URL-encode the conversationId since it may contain special characters like + in phone numbers
    guard
      let encodedConversationId = conversationId.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed)
    else {
      throw BridgeError.requestFailed
    }

    var components = URLComponents(
      url: serverURL.appendingPathComponent("conversations/\(encodedConversationId)/messages"),
      resolvingAgainstBaseURL: false
    )
    guard components != nil else {
      throw BridgeError.requestFailed
    }
    components!.queryItems = [
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "offset", value: String(offset)),
    ]

    guard let url = components!.url else {
      throw BridgeError.requestFailed
    }

    var request = URLRequest(url: url)
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    if e2eEnabled {
      request.addValue("enabled", forHTTPHeaderField: "X-E2E-Encryption")
    }

    let (data, httpResponse) = try await urlSession.data(for: request)

    guard let response = httpResponse as? HTTPURLResponse,
      response.statusCode == 200
    else {
      throw BridgeError.requestFailed
    }

    let messagesResponse = try decryptResponse(data, as: MessagesResponse.self)
    return messagesResponse.messages.map { $0.toMessage() }
  }

  public func sendMessage(text: String, to recipient: String) async throws {
    guard let serverURL, let apiKey else {
      throw BridgeError.notConnected
    }

    var request = URLRequest(url: serverURL.appendingPathComponent("send"))
    request.httpMethod = "POST"
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ["to": recipient, "text": text]

    // Encrypt request body if E2E is enabled
    if e2eEnabled, let encryption {
      request.addValue("enabled", forHTTPHeaderField: "X-E2E-Encryption")
      let encryptedPayload = try encryption.encrypt(body)
      let envelope = EncryptedEnvelope(version: 1, payload: encryptedPayload)
      request.httpBody = try JSONEncoder().encode(envelope)
    } else {
      request.httpBody = try JSONEncoder().encode(body)
    }

    let (data, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      throw BridgeError.sendFailed
    }

    // Verify the response is valid (server returns SendResponse)
    let sendResponse = try decryptResponse(data, as: SendResponse.self)
    if !sendResponse.success {
      throw BridgeError.sendFailed
    }
  }

  public func markConversationAsRead(_ conversationId: String) async throws {
    guard let serverURL, let apiKey else {
      throw BridgeError.notConnected
    }

    // URL-encode the conversationId since it may contain special characters like + in phone numbers
    guard
      let encodedConversationId = conversationId.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed)
    else {
      throw BridgeError.requestFailed
    }

    var request = URLRequest(
      url: serverURL.appendingPathComponent("conversations/\(encodedConversationId)/read"))
    request.httpMethod = "POST"
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")

    let (_, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      throw BridgeError.requestFailed
    }
  }

  public func sendTapback(type: TapbackType, messageGUID: String, action: TapbackActionType)
    async throws
  {
    guard let serverURL, let apiKey else {
      throw BridgeError.notConnected
    }

    // URL-encode the messageGUID since it may contain special characters
    guard
      let encodedMessageGUID = messageGUID.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed)
    else {
      throw BridgeError.requestFailed
    }

    var request = URLRequest(
      url: serverURL.appendingPathComponent("messages/\(encodedMessageGUID)/tapback"))
    request.httpMethod = "POST"
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "type": type.rawValue,
      "action": action.rawValue,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      throw BridgeError.tapbackFailed
    }
  }

  public func fetchAttachment(id: Int64) async throws -> Data {
    guard let serverURL, let apiKey else {
      throw BridgeError.notConnected
    }

    let url = serverURL.appendingPathComponent("attachments/\(id)")
    var request = URLRequest(url: url)
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    // Note: Attachments are served as raw binary, not encrypted
    // E2E encryption only applies to JSON API responses

    let (data, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw BridgeError.requestFailed
    }

    switch httpResponse.statusCode {
    case 200:
      return data
    case 404:
      throw BridgeError.attachmentNotFound
    default:
      throw BridgeError.requestFailed
    }
  }

  public func startWebSocket(
    onNewMessage: @escaping NewMessageHandler,
    onTapbackEvent: @escaping TapbackEventHandler,
    onSyncWarning: @escaping SyncWarningHandler,
    onSyncWarningCleared: @escaping SyncWarningClearedHandler,
    onPinnedConversationsChanged: @escaping PinnedConversationsChangedHandler
  ) async throws {
    guard let serverURL, let apiKey else {
      throw BridgeError.notConnected
    }

    self.newMessageHandler = onNewMessage
    self.tapbackEventHandler = onTapbackEvent
    self.syncWarningHandler = onSyncWarning
    self.syncWarningClearedHandler = onSyncWarningCleared
    self.pinnedConversationsChangedHandler = onPinnedConversationsChanged

    // Convert HTTP URL to WebSocket URL
    var wsComponents = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
    wsComponents.scheme = serverURL.scheme == "https" ? "wss" : "ws"
    wsComponents.path = "/ws"
    wsComponents.queryItems = [
      URLQueryItem(name: "apiKey", value: apiKey),
      URLQueryItem(name: "e2e", value: e2eEnabled ? "enabled" : nil),
    ].compactMap { $0.value != nil ? $0 : nil }

    guard let wsURL = wsComponents.url else {
      throw BridgeError.connectionFailed
    }

    logInfo("Starting WebSocket connection to \(wsURL.absoluteString)")
    webSocketTask = urlSession.webSocketTask(with: wsURL)
    webSocketTask?.resume()

    // Start receiving messages
    receiveWebSocketMessage()
    logDebug("WebSocket receive loop started")
  }

  public func stopWebSocket() async {
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
    newMessageHandler = nil
    tapbackEventHandler = nil
    syncWarningHandler = nil
    syncWarningClearedHandler = nil
    pinnedConversationsChangedHandler = nil
  }

  private func receiveWebSocketMessage() {
    webSocketTask?.receive { [weak self] result in
      Task { [weak self] in
        await self?.handleWebSocketResult(result)
      }
    }
  }

  private func handleWebSocketResult(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
    switch result {
    case .success(let message):
      logDebug("WebSocket received message")
      switch message {
      case .string(let text):
        logDebug("WebSocket received text: \(text.prefix(100))...")
        handleWebSocketText(text)
      case .data(let data):
        logDebug("WebSocket received data: \(data.count) bytes")
        if let text = String(data: data, encoding: .utf8) {
          handleWebSocketText(text)
        }
      @unknown default:
        logDebug("WebSocket received unknown message type")
        break
      }
      // Continue receiving
      receiveWebSocketMessage()

    case .failure(let error):
      logError("WebSocket error", error: error)
    // Could implement reconnection logic here
    }
  }

  private func handleWebSocketText(_ text: String) {
    guard let data = text.data(using: .utf8) else { return }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
      // Get the actual data to decode (decrypt if E2E enabled)
      let messageData: Data
      if e2eEnabled, let encryption {
        let envelope = try decoder.decode(EncryptedEnvelope.self, from: data)
        let decrypted = try encryption.decrypt(envelope.payload)
        messageData = decrypted
      } else {
        messageData = data
      }

      // First decode just the type to determine message format
      let envelope = try decoder.decode(WebSocketEnvelope.self, from: messageData)

      switch envelope.type {
      case "new_message":
        let wsMessage = try decoder.decode(NewMessageWebSocketMessage.self, from: messageData)
        let processed = wsMessage.data.message
        let message = processed.toMessage()
        let sender = "Unknown"  // Server doesn't include sender name in ProcessedMessage

        // Log message age (time since message was created)
        let messageAge = Date().timeIntervalSince(message.date) * 1000
        logInfo("WebSocket: new_message received, age: \(Int(messageAge))ms, id: \(message.id)")

        newMessageHandler?(message, sender)

      case "tapback_added", "tapback_removed":
        let wsMessage = try decoder.decode(TapbackWebSocketMessage.self, from: messageData)
        let payload = wsMessage.data

        // Convert the raw tapbackType Int to TapbackType enum
        guard let tapbackType = TapbackType(rawValue: payload.tapbackType) else {
          logWarning("WebSocket: Unknown tapback type \(payload.tapbackType)")
          return
        }

        let event = TapbackEvent(
          messageGUID: payload.messageGUID,
          tapbackType: tapbackType,
          sender: payload.sender,
          isFromMe: payload.isFromMe,
          conversationId: payload.conversationId,
          isRemoval: envelope.type == "tapback_removed",
          emoji: payload.emoji
        )

        logInfo(
          "WebSocket: \(envelope.type) received for message \(payload.messageGUID), type: \(tapbackType.emoji)"
        )

        tapbackEventHandler?(event)

      case "sync_warning":
        let wsMessage = try decoder.decode(SyncWarningWebSocketMessage.self, from: messageData)
        logInfo(
          "WebSocket: sync_warning received for conversation \(wsMessage.data.conversationId): \(wsMessage.data.message)"
        )
        syncWarningHandler?(wsMessage.data)

      case "sync_warning_cleared":
        let wsMessage = try decoder.decode(
          SyncWarningClearedWebSocketMessage.self, from: messageData)
        logInfo(
          "WebSocket: sync_warning_cleared received for conversation \(wsMessage.data.conversationId)"
        )
        syncWarningClearedHandler?(wsMessage.data)

      case "pinned_conversations_changed":
        let wsMessage = try decoder.decode(
          PinnedConversationsWebSocketMessage.self, from: messageData)
        logInfo(
          "WebSocket: pinned_conversations_changed received with \(wsMessage.data.pinned.count) pins"
        )
        pinnedConversationsChangedHandler?(wsMessage.data)

      default:
        logDebug("WebSocket received \(envelope.type) message")
      }
    } catch {
      logError("Failed to decode WebSocket message", error: error)
    }
  }

  // MARK: - E2E Encryption Helpers

  /// Decrypt a response, handling both encrypted and plain responses
  private func decryptResponse<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    if e2eEnabled, let encryption {
      // Decode the encrypted envelope
      let envelope = try decoder.decode(EncryptedEnvelope.self, from: data)
      return try encryption.decrypt(envelope.payload, as: type)
    } else {
      return try decoder.decode(type, from: data)
    }
  }
}

public enum BridgeError: LocalizedError {
  case notConnected
  case connectionFailed
  case requestFailed
  case sendFailed
  case attachmentNotFound
  case tapbackFailed

  public var errorDescription: String? {
    switch self {
    case .notConnected:
      return "Not connected to server"
    case .connectionFailed:
      return "Failed to connect to server"
    case .requestFailed:
      return "Request failed"
    case .sendFailed:
      return "Failed to send message"
    case .attachmentNotFound:
      return "Attachment not found"
    case .tapbackFailed:
      return "Failed to send tapback"
    }
  }
}
