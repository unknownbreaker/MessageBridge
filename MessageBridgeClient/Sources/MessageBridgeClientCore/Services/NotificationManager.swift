import Foundation
import UserNotifications

/// Protocol for wrapping UNUserNotificationCenter for testability
public protocol NotificationCenterProtocol: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?)
}

/// Default implementation using the real UNUserNotificationCenter
public final class SystemNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init() {
        self.center = UNUserNotificationCenter.current()
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
        center.delegate = delegate
    }
}

/// Protocol for notification management
public protocol NotificationManagerProtocol: Sendable {
    func requestAuthorization() async throws -> Bool
    func showNotification(for message: Message, senderName: String) async throws
    func clearNotifications(for conversationId: String) async
}

/// Manages local notifications for new messages
public actor NotificationManager: NotificationManagerProtocol {
    private let notificationCenter: NotificationCenterProtocol

    public init(notificationCenter: NotificationCenterProtocol = SystemNotificationCenter()) {
        self.notificationCenter = notificationCenter
    }

    /// Request authorization to show notifications
    public func requestAuthorization() async throws -> Bool {
        try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Show a notification for a new message
    public func showNotification(for message: Message, senderName: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = message.text ?? "(attachment)"
        content.sound = .default
        content.userInfo = [
            "conversationId": message.conversationId,
            "messageId": message.id
        ]

        // Use message ID as identifier for deduplication
        let identifier = "message-\(message.id)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        try await notificationCenter.add(request)
    }

    /// Clear notifications for a specific conversation
    public func clearNotifications(for conversationId: String) async {
        // Remove notifications that match the conversation prefix
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ["conversation-\(conversationId)"])
    }
}
