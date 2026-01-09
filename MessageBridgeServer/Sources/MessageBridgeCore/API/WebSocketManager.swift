import Vapor

/// Connection info including WebSocket and encryption settings
private struct ConnectionInfo: Sendable {
    let webSocket: WebSocket
    let e2eEncryption: E2EEncryption?
}

/// Manages WebSocket connections and broadcasts messages to all connected clients
public actor WebSocketManager {
    private var connections: [UUID: ConnectionInfo] = [:]
    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    /// Add a new WebSocket connection
    /// - Parameters:
    ///   - ws: The WebSocket connection
    ///   - apiKey: If provided and e2eEnabled is true, enables E2E encryption for this connection
    ///   - e2eEnabled: Whether to enable E2E encryption
    public func addConnection(_ ws: WebSocket, apiKey: String? = nil, e2eEnabled: Bool = false) -> UUID {
        let id = UUID()
        let encryption = (e2eEnabled && apiKey != nil) ? E2EEncryption(apiKey: apiKey!) : nil
        connections[id] = ConnectionInfo(webSocket: ws, e2eEncryption: encryption)
        return id
    }

    /// Remove a WebSocket connection
    public func removeConnection(_ id: UUID) {
        connections.removeValue(forKey: id)
    }

    /// Get the number of active connections
    public var connectionCount: Int {
        connections.count
    }

    /// Broadcast a new message to all connected clients
    public func broadcastNewMessage(_ message: Message, sender: String?) async {
        let data = NewMessageData(from: message, sender: sender)
        let wsMessage = WebSocketMessage(type: .newMessage, data: data)

        await broadcast(wsMessage)
    }

    /// Send a connected confirmation to a specific client
    public func sendConnected(to id: UUID) async {
        guard let connInfo = connections[id] else { return }

        let data = ConnectedData()
        let wsMessage = WebSocketMessage(type: .connected, data: data)

        await send(wsMessage, to: connInfo)
    }

    /// Send an error to a specific client
    public func sendError(_ message: String, to id: UUID) async {
        guard let connInfo = connections[id] else { return }

        let data = ErrorData(message: message)
        let wsMessage = WebSocketMessage(type: .error, data: data)

        await send(wsMessage, to: connInfo)
    }

    // MARK: - Private Methods

    private func broadcast<T: Codable & Sendable>(_ message: WebSocketMessage<T>) async {
        for (_, connInfo) in connections {
            await send(message, to: connInfo)
        }
    }

    private func send<T: Codable & Sendable>(_ message: WebSocketMessage<T>, to connInfo: ConnectionInfo) async {
        do {
            let data = try encoder.encode(message)

            // If E2E encryption is enabled, encrypt the message
            let messageString: String
            if let encryption = connInfo.e2eEncryption {
                let encryptedPayload = try encryption.encrypt(data)
                let envelope = EncryptedEnvelope(version: 1, payload: encryptedPayload)
                let envelopeData = try JSONEncoder().encode(envelope)
                messageString = String(data: envelopeData, encoding: .utf8) ?? ""
            } else {
                messageString = String(data: data, encoding: .utf8) ?? ""
            }

            if !messageString.isEmpty {
                try await connInfo.webSocket.send(messageString)
            }
        } catch {
            // Log error but don't crash - client may have disconnected
        }
    }
}
