import Foundation

/// Callback for receiving new messages via WebSocket
public typealias NewMessageHandler = @Sendable (Message, String) -> Void

/// Protocol defining the bridge service interface for testability
public protocol BridgeServiceProtocol: Sendable {
    func connect(to url: URL, apiKey: String, e2eEnabled: Bool) async throws
    func fetchConversations(limit: Int, offset: Int) async throws -> [Conversation]
    func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message]
    func sendMessage(text: String, to recipient: String) async throws -> Message
    func startWebSocket(onNewMessage: @escaping NewMessageHandler) async throws
    func stopWebSocket() async
}

/// WebSocket message types matching server format
struct WebSocketMessage: Codable {
    let type: String
    let data: WebSocketMessageData?
}

struct WebSocketMessageData: Codable {
    let id: Int64
    let conversationId: String
    let text: String?
    let sender: String?
    let date: Date
    let isFromMe: Bool
}

/// Handles communication with the MessageBridge server
public actor BridgeConnection: BridgeServiceProtocol {
    private var serverURL: URL?
    private var apiKey: String?
    private var urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var newMessageHandler: NewMessageHandler?
    private var e2eEnabled: Bool = false
    private var encryption: E2EEncryption?

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
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

        var components = URLComponents(url: serverURL.appendingPathComponent("conversations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        var request = URLRequest(url: components.url!)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        if e2eEnabled {
            request.addValue("enabled", forHTTPHeaderField: "X-E2E-Encryption")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.requestFailed
        }

        return try decryptResponse(data, as: [Conversation].self)
    }

    public func fetchMessages(conversationId: String, limit: Int = 50, offset: Int = 0) async throws -> [Message] {
        guard let serverURL, let apiKey else {
            throw BridgeError.notConnected
        }

        var components = URLComponents(
            url: serverURL.appendingPathComponent("conversations/\(conversationId)/messages"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        var request = URLRequest(url: components.url!)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        if e2eEnabled {
            request.addValue("enabled", forHTTPHeaderField: "X-E2E-Encryption")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.requestFailed
        }

        return try decryptResponse(data, as: [Message].self)
    }

    public func sendMessage(text: String, to recipient: String) async throws -> Message {
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
              httpResponse.statusCode == 200 else {
            throw BridgeError.sendFailed
        }

        return try decryptResponse(data, as: Message.self)
    }

    public func startWebSocket(onNewMessage: @escaping NewMessageHandler) async throws {
        guard let serverURL, let apiKey else {
            throw BridgeError.notConnected
        }

        self.newMessageHandler = onNewMessage

        // Convert HTTP URL to WebSocket URL
        var wsComponents = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        wsComponents.scheme = serverURL.scheme == "https" ? "wss" : "ws"
        wsComponents.path = "/ws"
        wsComponents.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "e2e", value: e2eEnabled ? "enabled" : nil)
        ].compactMap { $0.value != nil ? $0 : nil }

        guard let wsURL = wsComponents.url else {
            throw BridgeError.connectionFailed
        }

        webSocketTask = urlSession.webSocketTask(with: wsURL)
        webSocketTask?.resume()

        // Start receiving messages
        receiveWebSocketMessage()
    }

    public func stopWebSocket() async {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        newMessageHandler = nil
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
            switch message {
            case .string(let text):
                handleWebSocketText(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleWebSocketText(text)
                }
            @unknown default:
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
            // Try to decrypt if E2E is enabled
            let wsMessage: WebSocketMessage
            if e2eEnabled, let encryption {
                // First decode as envelope
                let envelope = try decoder.decode(EncryptedEnvelope.self, from: data)
                wsMessage = try encryption.decrypt(envelope.payload, as: WebSocketMessage.self)
            } else {
                wsMessage = try decoder.decode(WebSocketMessage.self, from: data)
            }

            if wsMessage.type == "new_message", let messageData = wsMessage.data {
                let message = Message(
                    id: messageData.id,
                    guid: "ws-\(messageData.id)",
                    text: messageData.text,
                    date: messageData.date,
                    isFromMe: messageData.isFromMe,
                    handleId: nil,
                    conversationId: messageData.conversationId
                )
                let sender = messageData.sender ?? "Unknown"
                newMessageHandler?(message, sender)
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
        }
    }
}
