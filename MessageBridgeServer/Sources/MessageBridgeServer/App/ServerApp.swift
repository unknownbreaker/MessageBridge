import SwiftUI
import AppKit
import MessageBridgeCore
import ServiceManagement

// Window manager to handle opening windows from menu bar
class WindowManager: ObservableObject {
    static let shared = WindowManager()

    var settingsWindow: NSWindow?
    var logsWindow: NSWindow?
    var aboutWindow: NSWindow?
    weak var appState: AppState?

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let appState = appState else { return }

        let settingsView = SettingsView().environmentObject(appState)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window
    }

    func openLogs() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = logsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let appState = appState else { return }

        let logsView = LogViewerView().environmentObject(appState)
        let hostingController = NSHostingController(rootView: logsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Server Logs"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.logsWindow = window
    }

    func openAbout() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "About MessageBridge Server"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 350, height: 300))
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.aboutWindow = window
    }
}

@main
struct ServerApp: App {
    @StateObject private var appState = AppState()

    init() {
        // WindowManager.shared.appState will be set when menu appears
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appState: appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        // Status section
        Text("MessageBridge Server")
            .font(.headline)
        Text(appState.serverStatus.displayText)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        // Server controls
        if appState.serverStatus.isRunning {
            Button("Stop Server") {
                debugLog("Stop Server clicked")
                Task { await appState.stopServer() }
            }
            Button("Restart Server") {
                debugLog("Restart Server clicked")
                Task { await appState.restartServer() }
            }
        } else {
            Button("Start Server") {
                debugLog("Start Server clicked")
                Task { await appState.startServer() }
            }
            .disabled(appState.apiKey.isEmpty)
        }

        Divider()

        Button("Copy API Key") {
            debugLog("Copy API Key clicked")
            appState.copyAPIKey()
        }

        Divider()

        Button("View Logs...") {
            debugLog("View Logs clicked")
            WindowManager.shared.appState = appState
            WindowManager.shared.openLogs()
        }

        Button("Settings...") {
            debugLog("Settings clicked")
            WindowManager.shared.appState = appState
            WindowManager.shared.openSettings()
        }

        Divider()

        Button("About MessageBridge Server") {
            debugLog("About clicked")
            WindowManager.shared.openAbout()
        }

        Divider()

        Button("Quit") {
            debugLog("Quit clicked")
            Task {
                await appState.stopServer()
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var serverStatus: ServerStatus = .stopped
    @Published var apiKey: String = ""
    @Published var port: Int = 8080
    @Published var startAtLogin: Bool = false
    @Published var debugLoggingEnabled: Bool = false
    @Published var logs: [LogEntry] = []

    // Tunnel Providers
    @Published var selectedTunnelProvider: TunnelProvider = .cloudflare
    @Published var cloudfareTunnelStatus: TunnelStatus = .stopped
    @Published var ngrokTunnelStatus: TunnelStatus = .stopped
    @Published var cloudflaredInfo: CloudflaredInfo?
    @Published var ngrokInfo: NgrokInfo?

    let serverManager = ServerManager()
    let cloudflaredManager = CloudflaredManager()
    let ngrokManager = NgrokManager()

    // Legacy computed property for backward compatibility
    var tunnelStatus: TunnelStatus {
        switch selectedTunnelProvider {
        case .cloudflare: return cloudfareTunnelStatus
        case .ngrok: return ngrokTunnelStatus
        }
    }

    var menuBarIcon: String {
        switch serverStatus {
        case .stopped: return "bubble.left.and.bubble.right"
        case .starting: return "bubble.left.and.bubble.right"
        case .running: return "bubble.left.and.bubble.right.fill"
        case .error: return "exclamationmark.bubble"
        }
    }

    var menuBarIconColor: Color {
        switch serverStatus {
        case .stopped: return .secondary
        case .starting: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }

    init() {
        loadSettings()
        setupTunnelStatusHandlers()

        // Check tunnel binary installations and auto-start server if enabled
        Task {
            await checkTunnelInstallations()

            if startAtLogin && !apiKey.isEmpty {
                await startServer()
            }
        }
    }

    func startServer() async {
        guard !apiKey.isEmpty else {
            serverStatus = .error("API key not configured")
            return
        }

        do {
            try await serverManager.start(port: port, apiKey: apiKey)
            serverStatus = await serverManager.status
            addLog(level: .info, message: "Server started on port \(port)")
        } catch {
            serverStatus = .error(error.localizedDescription)
            addLog(level: .error, message: "Failed to start server: \(error.localizedDescription)")
        }
    }

    func stopServer() async {
        await serverManager.stop()
        serverStatus = await serverManager.status
        addLog(level: .info, message: "Server stopped")
    }

    func restartServer() async {
        addLog(level: .info, message: "Restarting server...")
        do {
            try await serverManager.restart(port: port, apiKey: apiKey)
            serverStatus = await serverManager.status
            addLog(level: .info, message: "Server restarted on port \(port)")
        } catch {
            serverStatus = .error(error.localizedDescription)
            addLog(level: .error, message: "Failed to restart server: \(error.localizedDescription)")
        }
    }

    func generateNewAPIKey() {
        apiKey = UUID().uuidString
        saveSettings()
        addLog(level: .info, message: "Generated new API key")
    }

    func copyAPIKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(apiKey, forType: .string)
        addLog(level: .debug, message: "API key copied to clipboard")
    }

    // MARK: - Tunnel Management

    func setupTunnelStatusHandlers() {
        Task {
            await cloudflaredManager.onStatusChange { [weak self] status in
                Task { @MainActor in
                    self?.cloudfareTunnelStatus = status
                }
            }
            await ngrokManager.onStatusChange { [weak self] status in
                Task { @MainActor in
                    self?.ngrokTunnelStatus = status
                }
            }
        }
    }

    func checkTunnelInstallations() async {
        // Check cloudflared
        let cloudflaredInstalled = await cloudflaredManager.isInstalled()
        if cloudflaredInstalled {
            cloudflaredInfo = await cloudflaredManager.getInfo()
            cloudfareTunnelStatus = .stopped
        } else {
            cloudfareTunnelStatus = .notInstalled
            cloudflaredInfo = nil
        }

        // Check ngrok
        let ngrokInstalled = await ngrokManager.isInstalled()
        if ngrokInstalled {
            ngrokInfo = await ngrokManager.getInfo()
            ngrokTunnelStatus = .stopped
        } else {
            ngrokTunnelStatus = .notInstalled
            ngrokInfo = nil
        }
    }

    // MARK: - Cloudflare Tunnel

    func installCloudflared() async throws {
        addLog(level: .info, message: "Installing cloudflared...")
        try await cloudflaredManager.install()
        cloudflaredInfo = await cloudflaredManager.getInfo()
        cloudfareTunnelStatus = .stopped
        addLog(level: .info, message: "cloudflared installed successfully")
    }

    func startCloudfareTunnel() async throws {
        guard serverStatus.isRunning else {
            throw CloudflaredError.failedToStart("Server must be running first")
        }
        addLog(level: .info, message: "Starting Cloudflare Tunnel...")
        let url = try await cloudflaredManager.startQuickTunnel(port: port)
        addLog(level: .info, message: "Cloudflare Tunnel started: \(url)")
    }

    func stopCloudfareTunnel() async {
        addLog(level: .info, message: "Stopping Cloudflare Tunnel...")
        await cloudflaredManager.stopTunnel()
        addLog(level: .info, message: "Cloudflare Tunnel stopped")
    }

    // Legacy methods for backward compatibility
    func startTunnel() async throws {
        try await startCloudfareTunnel()
    }

    func stopTunnel() async {
        await stopCloudfareTunnel()
    }

    // MARK: - ngrok Tunnel

    func installNgrok() async throws {
        addLog(level: .info, message: "Installing ngrok...")
        try await ngrokManager.install()
        ngrokInfo = await ngrokManager.getInfo()
        ngrokTunnelStatus = .stopped
        addLog(level: .info, message: "ngrok installed successfully")
    }

    func startNgrokTunnel() async throws {
        guard serverStatus.isRunning else {
            throw NgrokError.failedToStart("Server must be running first")
        }
        addLog(level: .info, message: "Starting ngrok tunnel...")
        let url = try await ngrokManager.startTunnel(port: port)
        addLog(level: .info, message: "ngrok tunnel started: \(url)")
    }

    func stopNgrokTunnel() async {
        addLog(level: .info, message: "Stopping ngrok tunnel...")
        await ngrokManager.stopTunnel()
        addLog(level: .info, message: "ngrok tunnel stopped")
    }

    // MARK: - Shared Tunnel Helpers

    func copyTunnelURL() {
        if let url = tunnelStatus.url {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            addLog(level: .debug, message: "Tunnel URL copied to clipboard")
        }
    }

    // MARK: - Settings Persistence

    private let keychainManager = KeychainManager()

    private func loadSettings() {
        // Load API key from Keychain
        if let storedKey = try? keychainManager.retrieveAPIKey() {
            apiKey = storedKey
        } else {
            // Generate new key if none exists
            apiKey = keychainManager.generateAPIKey()
            try? keychainManager.saveAPIKey(apiKey)
        }

        // Load other settings from UserDefaults
        port = UserDefaults.standard.integer(forKey: "serverPort")
        if port == 0 { port = 8080 }

        startAtLogin = UserDefaults.standard.bool(forKey: "startAtLogin")
        debugLoggingEnabled = UserDefaults.standard.bool(forKey: "debugLoggingEnabled")

        // Load tunnel provider
        if let providerRaw = UserDefaults.standard.string(forKey: "tunnelProvider"),
           let provider = TunnelProvider(rawValue: providerRaw) {
            selectedTunnelProvider = provider
        }
    }

    func saveSettings() {
        // Save API key to Keychain
        try? keychainManager.saveAPIKey(apiKey)

        // Save other settings to UserDefaults
        UserDefaults.standard.set(port, forKey: "serverPort")
        UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
        UserDefaults.standard.set(debugLoggingEnabled, forKey: "debugLoggingEnabled")
        UserDefaults.standard.set(selectedTunnelProvider.rawValue, forKey: "tunnelProvider")

        // Update login item
        updateLoginItem()
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if startAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // This typically fails during development when app isn't code-signed
                // or not in /Applications - only log at debug level
                debugLog("Failed to update login item: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Logging

    func addLog(level: LogLevel, message: String) {
        let entry = LogEntry(
            level: level,
            message: message,
            file: #file,
            function: #function,
            line: #line
        )
        logs.insert(entry, at: 0)

        // Keep only last 1000 logs
        if logs.count > 1000 {
            logs = Array(logs.prefix(1000))
        }
    }

    func clearLogs() {
        logs.removeAll()
    }
}

// MARK: - Log Entry (Server-side version)

public enum LogLevel: Int, Codable, Comparable, CaseIterable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }

    public var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct LogEntry: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let file: String
    public let function: String
    public let line: Int

    public init(level: LogLevel, message: String, file: String, function: String, line: Int) {
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.file = file
        self.function = function
        self.line = line
    }

    public var fileName: String {
        (file as NSString).lastPathComponent
    }
}
