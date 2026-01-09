import Vapor

/// Manages WebSocket connections and broadcasts messages to all connected clients
public actor WebSocketManager {
    private var connections: [UUID: WebSocket] = [:]
    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    /// Add a new WebSocket connection
    public func addConnection(_ ws: WebSocket) -> UUID {
        let id = UUID()
        connections[id] = ws
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
        guard let ws = connections[id] else { return }

        let data = ConnectedData()
        let wsMessage = WebSocketMessage(type: .connected, data: data)

        await send(wsMessage, to: ws)
    }

    /// Send an error to a specific client
    public func sendError(_ message: String, to id: UUID) async {
        guard let ws = connections[id] else { return }

        let data = ErrorData(message: message)
        let wsMessage = WebSocketMessage(type: .error, data: data)

        await send(wsMessage, to: ws)
    }

    // MARK: - Private Methods

    private func broadcast<T: Codable & Sendable>(_ message: WebSocketMessage<T>) async {
        for (_, ws) in connections {
            await send(message, to: ws)
        }
    }

    private func send<T: Codable & Sendable>(_ message: WebSocketMessage<T>, to ws: WebSocket) async {
        do {
            let data = try encoder.encode(message)
            if let string = String(data: data, encoding: .utf8) {
                try await ws.send(string)
            }
        } catch {
            // Log error but don't crash - client may have disconnected
        }
    }
}
