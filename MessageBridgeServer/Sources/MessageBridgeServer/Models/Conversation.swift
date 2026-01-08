import Foundation

/// Represents a chat conversation (1:1 or group)
struct Conversation: Codable, Identifiable, Sendable {
    let id: String               // chat_identifier from database
    let guid: String             // Unique GUID
    let displayName: String?     // User-set name for group chats
    let participants: [Handle]   // Contacts in this conversation
    let lastMessage: Message?    // Most recent message
    let isGroup: Bool            // True if more than one participant

    /// Best display name for this conversation
    var resolvedDisplayName: String {
        if let name = displayName, !name.isEmpty {
            return name
        }
        if participants.count == 1 {
            return participants[0].displayAddress
        }
        if participants.isEmpty {
            return "Unknown"
        }
        // Group without name: show first few participants
        let names = participants.prefix(3).map { $0.displayAddress }
        let suffix = participants.count > 3 ? " +\(participants.count - 3)" : ""
        return names.joined(separator: ", ") + suffix
    }
}
