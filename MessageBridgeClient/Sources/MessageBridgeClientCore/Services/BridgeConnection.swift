import Foundation

/// Protocol defining the bridge service interface for testability
public protocol BridgeServiceProtocol: Sendable {
    func connect(to url: URL, apiKey: String) async throws
    func fetchConversations(limit: Int, offset: Int) async throws -> [Conversation]
    func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message]
    func sendMessage(text: String, to recipient: String) async throws -> Message
}

/// Handles communication with the MessageBridge server
public actor BridgeConnection: BridgeServiceProtocol {
    private var serverURL: URL?
    private var apiKey: String?
    private var urlSession: URLSession

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
