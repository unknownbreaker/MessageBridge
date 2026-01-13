import Foundation
import Vapor

/// Represents a chat conversation (1:1 or group)
public struct Conversation: Content, Identifiable, Sendable {
    public let id: String               // chat_identifier from database
    public let guid: String             // Unique GUID
    public let displayName: String?     // User-set name for group chats
    public let participants: [Handle]   // Contacts in this conversation
    public let lastMessage: Message?    // Most recent message
    public let isGroup: Bool            // True if more than one participant

    public init(id: String, guid: String, displayName: String?, participants: [Handle], lastMessage: Message?, isGroup: Bool) {
        self.id = id
        self.guid = guid
        self.displayName = displayName
        self.participants = participants
        self.lastMessage = lastMessage
        self.isGroup = isGroup
    }

    /// Best display name for this conversation
    public var resolvedDisplayName: String {
        if let name = displayName, !name.isEmpty {
            return name
        }
        if participants.count == 1 {
            return participants[0].displayName
        }
        if participants.isEmpty {
            return "Unknown"
        }
        // Group without name: show first few participants
        let names = participants.prefix(3).map { $0.displayName }
        let suffix = participants.count > 3 ? " +\(participants.count - 3)" : ""
        return names.joined(separator: ", ") + suffix
    }
}
