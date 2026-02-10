import UserNotifications
import XCTest

@testable import MessageBridgeClientCore

/// Mock implementation of UNUserNotificationCenter for testing
final class MockNotificationCenter: NotificationCenterProtocol {
  var requestAuthorizationCalled = false
  var addNotificationCalled = false
  var removeNotificationsCalled = false
  var lastNotificationRequest: UNNotificationRequest?
  var authorizationGranted = true
  var authorizationError: Error?
  var delegateSet = false

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    requestAuthorizationCalled = true
    if let error = authorizationError {
      throw error
    }
    return authorizationGranted
  }

  func add(_ request: UNNotificationRequest) async throws {
    addNotificationCalled = true
    lastNotificationRequest = request
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    removeNotificationsCalled = true
  }

  func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
    delegateSet = true
  }
}

final class NotificationManagerTests: XCTestCase {

  // MARK: - Authorization Tests

  func testRequestAuthorization_callsNotificationCenter() async throws {
    let mockCenter = MockNotificationCenter()
    let manager = NotificationManager(notificationCenter: mockCenter)

    _ = try await manager.requestAuthorization()

    XCTAssertTrue(mockCenter.requestAuthorizationCalled)
  }

  func testRequestAuthorization_whenGranted_returnsTrue() async throws {
    let mockCenter = MockNotificationCenter()
    mockCenter.authorizationGranted = true
    let manager = NotificationManager(notificationCenter: mockCenter)

    let granted = try await manager.requestAuthorization()

    XCTAssertTrue(granted)
  }

  func testRequestAuthorization_whenDenied_returnsFalse() async throws {
    let mockCenter = MockNotificationCenter()
    mockCenter.authorizationGranted = false
    let manager = NotificationManager(notificationCenter: mockCenter)

    let granted = try await manager.requestAuthorization()

    XCTAssertFalse(granted)
  }

  // MARK: - Show Notification Tests

  func testShowNotification_createsNotificationRequest() async throws {
    let mockCenter = MockNotificationCenter()
    let manager = NotificationManager(notificationCenter: mockCenter)

    let message = Message(
      id: 1,
      guid: "msg-1",
      text: "Hello there!",
      date: Date(),
      isFromMe: false,
      handleId: 1,
      conversationId: "chat-1"
    )

    try await manager.showNotification(for: message, senderName: "John Doe")

    XCTAssertTrue(mockCenter.addNotificationCalled)
    XCTAssertNotNil(mockCenter.lastNotificationRequest)
  }

  func testShowNotification_setsCorrectTitle() async throws {
    let mockCenter = MockNotificationCenter()
    let manager = NotificationManager(notificationCenter: mockCenter)

    let message = Message(
      id: 1,
      guid: "msg-1",
      text: "Hello there!",
      date: Date(),
      isFromMe: false,
      handleId: 1,
      conversationId: "chat-1"
    )

    try await manager.showNotification(for: message, senderName: "John Doe")

    let content = mockCenter.lastNotificationRequest?.content
    XCTAssertEqual(content?.title, "John Doe")
  }

  func testShowNotification_setsCorrectBody() async throws {
    let mockCenter = MockNotificationCenter()
    let manager = NotificationManager(notificationCenter: mockCenter)

    let message = Message(
      id: 1,
      guid: "msg-1",
      text: "Hello there!",
      date: Date(),
      isFromMe: false,
      handleId: 1,
      conversationId: "chat-1"
    )

    try await manager.showNotification(for: message, senderName: "John Doe")

    let content = mockCenter.lastNotificationRequest?.content
    XCTAssertEqual(content?.body, "Hello there!")
  }

  func testShowNotification_includesConversationIdInUserInfo() async throws {
    let mockCenter = MockNotificationCenter()
    let manager = NotificationManager(notificationCenter: mockCenter)

    let message = Message(
      id: 1,
      guid: "msg-1",
      text: "Hello there!",
      date: Date(),
      isFromMe: false,
      handleId: 1,
      conversationId: "chat-1"
    )

    try await manager.showNotification(for: message, senderName: "John Doe")

    let userInfo = mockCenter.lastNotificationRequest?.content.userInfo
    XCTAssertEqual(userInfo?["conversationId"] as? String, "chat-1")
  }

  func testShowNotification_withNilText_usesAttachmentPlaceholder() async throws {
    let mockCenter = MockNotificationCenter()
    let manager = NotificationManager(notificationCenter: mockCenter)

    let message = Message(
      id: 1,
      guid: "msg-1",
      text: nil,
      date: Date(),
      isFromMe: false,
      handleId: 1,
      conversationId: "chat-1"
    )

    try await manager.showNotification(for: message, senderName: "John Doe")

    let content = mockCenter.lastNotificationRequest?.content
    XCTAssertEqual(content?.body, "(attachment)")
  }

  // MARK: - Clear Notifications Tests

  func testClearNotifications_callsRemoveDeliveredNotifications() async {
    let mockCenter = MockNotificationCenter()
    let manager = NotificationManager(notificationCenter: mockCenter)

    await manager.clearNotifications(for: "chat-1")

    XCTAssertTrue(mockCenter.removeNotificationsCalled)
  }
}
