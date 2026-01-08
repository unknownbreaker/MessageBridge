import Foundation
import Vapor

/// Represents a single message in a conversation
public struct Message: Content, Identifiable, Sendable {
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

    /// Whether this message has text content (vs attachment-only or reaction)
    public var hasText: Bool {
        guard let text = text else { return false }
        return !text.isEmpty
    }
}

// MARK: - Date Conversion Utilities

extension Message {
    /// Apple's Messages database stores dates as nanoseconds since 2001-01-01 (Core Data reference date)
    /// This converts the raw database timestamp to a Swift Date
    public static func dateFromAppleTimestamp(_ timestamp: Int64) -> Date {
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
