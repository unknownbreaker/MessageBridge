import SwiftUI
import UserNotifications
import MessageBridgeClientCore

@main
struct MessageBridgeApp: App {
    @StateObject private var viewModel = MessagesViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    // TODO: Implement new message sheet
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            // Note: Cmd+F is automatically handled by .searchable modifier

            CommandGroup(after: .appSettings) {
                Button("View Logs...") {
                    openWindow(id: "log-viewer")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Window("Logs", id: "log-viewer") {
            LogViewerView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate for Notification Handling

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var viewModel: MessagesViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner and play sound even when app is in foreground
        // (but only if the conversation is not currently selected)
        return [.banner, .sound]
    }

    // Handle notification click
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        if let conversationId = userInfo["conversationId"] as? String {
            await MainActor.run {
                // Navigate to the conversation
                NotificationCenter.default.post(
                    name: .openConversation,
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openConversation = Notification.Name("openConversation")
}
