import Foundation

// MARK: - Handle

struct Handle: Codable, Identifiable, Hashable {
    let id: Int64
    let address: String
    let service: String

    var displayAddress: String {
        address
    }
}

// MARK: - Message

struct Message: Codable, Identifiable, Hashable {
    let id: Int64
    let guid: String
    let text: String?
    let date: Date
    let isFromMe: Bool
    let handleId: Int64?
    let conversationId: String

    var hasText: Bool {
        guard let text = text else { return false }
        return !text.isEmpty
    }
}

// MARK: - Conversation

struct Conversation: Codable, Identifiable, Hashable {
    let id: String
    let guid: String
    private let _displayName: String?
    let participants: [Handle]
    let lastMessage: Message?
    let isGroup: Bool

    enum CodingKeys: String, CodingKey {
        case id, guid, participants, lastMessage, isGroup
        case _displayName = "displayName"
    }

    init(id: String, guid: String, displayName: String?, participants: [Handle], lastMessage: Message?, isGroup: Bool) {
        self.id = id
        self.guid = guid
        self._displayName = displayName
        self.participants = participants
        self.lastMessage = lastMessage
        self.isGroup = isGroup
    }

    var displayName: String {
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
