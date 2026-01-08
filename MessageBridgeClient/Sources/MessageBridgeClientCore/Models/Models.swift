import Foundation

// MARK: - Handle

public struct Handle: Codable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let address: String
    public let service: String

    public init(id: Int64, address: String, service: String) {
        self.id = id
        self.address = address
        self.service = service
    }

    public var displayAddress: String {
        address
    }
}

// MARK: - Message

public struct Message: Codable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let guid: String
    public let text: String?
    public let date: Date
    public let isFromMe: Bool
    public let handleId: Int64?
    public let conversationId: String

    public init(id: Int64, guid: String, text: String?, date: Date, isFromMe: Bool, handleId: Int64?, conversationId: String) {
        self.id = id
        self.guid = guid
        self.text = text
        self.date = date
        self.isFromMe = isFromMe
        self.handleId = handleId
        self.conversationId = conversationId
    }

    public var hasText: Bool {
        guard let text = text else { return false }
        return !text.isEmpty
    }
}

// MARK: - Conversation

public struct Conversation: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let guid: String
    private let _displayName: String?
    public let participants: [Handle]
    public let lastMessage: Message?
    public let isGroup: Bool

    enum CodingKeys: String, CodingKey {
        case id, guid, participants, lastMessage, isGroup
        case _displayName = "displayName"
    }

    public init(id: String, guid: String, displayName: String?, participants: [Handle], lastMessage: Message?, isGroup: Bool) {
        self.id = id
        self.guid = guid
        self._displayName = displayName
        self.participants = participants
        self.lastMessage = lastMessage
        self.isGroup = isGroup
    }

    public var displayName: String {
        if let name = _displayName, !name.isEmpty {
            return name
        }
        if participants.count == 1 {
            return participants[0].displayAddress
        }
        if participants.isEmpty {
            return "Unknown"
        }
        let names = participants.prefix(3).map { $0.displayAddress }
        let suffix = participants.count > 3 ? " +\(participants.count - 3)" : ""
        return names.joined(separator: ", ") + suffix
    }
}
