import MessageBridgeClientCore
import SwiftUI
import UserNotifications

@main
struct MessageBridgeApp: App {
  @StateObject private var viewModel = MessagesViewModel()
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.openWindow) private var openWindow

  private let keychainManager = KeychainManager()

  init() {
    setupRenderers()
    setupAttachmentRenderers()
    setupDecorators()
    setupActions()
    setupComposer()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(viewModel)
        .onAppear {
          appDelegate.viewModel = viewModel
        }
        .task {
          await autoConnect()
        }
    }
    .defaultSize(width: 950, height: 680)
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

      CommandGroup(after: .toolbar) {
        Button("Reconnect") {
          Task {
            await viewModel.reconnect()
          }
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(viewModel.connectionStatus == .connecting)
      }
    }

    Window("Logs", id: "log-viewer") {
      LogViewerView()
    }
    .windowResizability(.contentSize)

    Settings {
      SettingsView()
        .environmentObject(viewModel)
    }
  }

  private func setupAttachmentRenderers() {
    AttachmentRendererRegistry.shared.register(DocumentRenderer())
    AttachmentRendererRegistry.shared.register(SingleImageRenderer())
    AttachmentRendererRegistry.shared.register(VideoRenderer())
    AttachmentRendererRegistry.shared.register(AudioRenderer())
    AttachmentRendererRegistry.shared.register(ImageGalleryRenderer())
  }

  private func setupDecorators() {
    DecoratorRegistry.shared.register(TimestampDecorator())
    DecoratorRegistry.shared.register(TapbackDecorator())
    DecoratorRegistry.shared.register(ReadReceiptDecorator())
  }

  private func setupActions() {
    let registry = ActionRegistry.shared
    registry.register(CopyTextAction())
    registry.register(CopyCodeAction())
    registry.register(ReplyAction())
    registry.register(TapbackAction())
    registry.register(ForwardAction())
    registry.register(ShareAction())
    registry.register(TranslateAction())
    registry.register(DeleteAction())
    registry.register(UnsendAction())
  }

  private func setupComposer() {
    // No plugins registered yet — infrastructure ready for future plugins
    _ = ComposerRegistry.shared
  }

  private func setupRenderers() {
    RendererRegistry.shared.register(PlainTextRenderer())
    RendererRegistry.shared.register(LargeEmojiRenderer())
    RendererRegistry.shared.register(LinkPreviewRenderer())
    RendererRegistry.shared.register(HighlightedTextRenderer())
  }

  private func autoConnect() async {
    guard let config = try? keychainManager.retrieveServerConfig() else {
      logInfo("No saved server configuration, waiting for user to configure")
      return
    }

    await viewModel.connect(
      to: config.serverURL,
      apiKey: config.apiKey,
      e2eEnabled: config.e2eEnabled
    )
  }
}

// MARK: - App Delegate for Notification Handling

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  weak var viewModel: MessagesViewModel?

  func applicationWillFinishLaunching(_ notification: Notification) {
    // Clear any saved window/toolbar state to prevent crashes from incompatible state
    // This is necessary after changing toolbar configuration between versions
    UserDefaults.standard.removeObject(forKey: "NSToolbar Configuration com.apple.NSWindow.toolbar")
    UserDefaults.standard.removeObject(forKey: "NSWindow Frame main")

    // Also clear any SwiftUI-specific toolbar state
    if let bundleID = Bundle.main.bundleIdentifier {
      let savedStateURL = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first?
      .appendingPathComponent(bundleID)
      .appendingPathComponent("Saved Application State")
      if let url = savedStateURL, FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
  }

  // Disable state restoration to prevent crashes from incompatible saved toolbar state
  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return false
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
