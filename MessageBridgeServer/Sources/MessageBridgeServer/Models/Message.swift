import Foundation

/// Represents a single message in a conversation
struct Message: Codable, Identifiable, Sendable {
    let id: Int64
    let guid: String
    let text: String?
    let date: Date
    let isFromMe: Bool
    let handleId: Int64?
    let conversationId: String

    /// Whether this message has text content (vs attachment-only or reaction)
    var hasText: Bool {
        guard let text = text else { return false }
        return !text.isEmpty
    }
}

// MARK: - Date Conversion Utilities

extension Message {
    /// Apple's Messages database stores dates as nanoseconds since 2001-01-01 (Core Data reference date)
    /// This converts the raw database timestamp to a Swift Date
    static func dateFromAppleTimestamp(_ timestamp: Int64) -> Date {
        // Timestamps after ~2017 are in nanoseconds
        // Earlier timestamps might be in seconds - detect based on magnitude
        let seconds: TimeInterval
        if timestamp > 1_000_000_000_000 {
            // Nanoseconds
            seconds = TimeInterval(timestamp) / 1_000_000_000
        } else {
            // Already in seconds (older messages)
            seconds = TimeInterval(timestamp)
        }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}
