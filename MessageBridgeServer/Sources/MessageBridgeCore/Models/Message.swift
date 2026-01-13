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

// MARK: - Attributed Body Text Extraction

extension Message {
    /// Extracts plain text from an attributedBody blob (NSArchiver streamtyped format)
    /// Used when the text field is NULL but attributedBody contains the message content
    /// Note: Apple's Messages database uses the legacy streamtyped format, not NSKeyedArchiver
    public static func extractTextFromAttributedBody(_ data: Data) -> String? {
        // The attributedBody uses Apple's legacy "streamtyped" format (NSArchiver)
        // NSUnarchiver is deprecated but is the only way to read this format
        guard let unarchiver = NSUnarchiver(forReadingWith: data) else {
            return nil
        }

        // Decode the root object (should be NSAttributedString or NSMutableAttributedString)
        guard let obj = unarchiver.decodeObject(),
              let attributedString = obj as? NSAttributedString else {
            return nil
        }

        let text = attributedString.string
        return text.isEmpty ? nil : text
    }
}
