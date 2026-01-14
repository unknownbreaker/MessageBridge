import Foundation
import UserNotifications

/// Notification for when user taps a notification to open a conversation
public extension Notification.Name {
    static let openConversation = Notification.Name("openConversation")
}

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

/// Delegate to handle notification presentation and user interactions
public final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationDelegate()

    private override init() {
        super.init()
    }

    /// Handle notification presentation when app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Don't show notifications when app is active - user can already see messages
        completionHandler([])
    }

    /// Handle user tapping on a notification
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let conversationId = userInfo["conversationId"] as? String {
            // Post notification to open the conversation
            NotificationCenter.default.post(
                name: .openConversation,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }

        completionHandler()
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
        // Set delegate to allow foreground notifications and handle taps
        notificationCenter.setDelegate(NotificationDelegate.shared)
        return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
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
