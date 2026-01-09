import Foundation

/// Callback for receiving new messages via WebSocket
public typealias NewMessageHandler = @Sendable (Message, String) -> Void

/// Protocol defining the bridge service interface for testability
public protocol BridgeServiceProtocol: Sendable {
    func connect(to url: URL, apiKey: String) async throws
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

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
    }

    public func connect(to url: URL, apiKey: String) async throws {
        self.serverURL = url
        self.apiKey = apiKey

        // Test connection with health check
        let healthURL = url.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
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

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Conversation].self, from: data)
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

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Message].self, from: data)
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
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.sendFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Message.self, from: data)
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
        wsComponents.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]

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
            print("WebSocket error: \(error)")
            // Could implement reconnection logic here
        }
    }

    private func handleWebSocketText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let wsMessage = try decoder.decode(WebSocketMessage.self, from: data)

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
            print("Failed to decode WebSocket message: \(error)")
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
