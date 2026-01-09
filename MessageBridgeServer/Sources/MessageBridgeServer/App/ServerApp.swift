import SwiftUI
import MessageBridgeCore
import ServiceManagement

@main
struct ServerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ServerMenuView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(appState.menuBarIconColor, .primary)
            }
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // Log viewer window
        Window("Server Logs", id: "log-viewer") {
            LogViewerView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var serverStatus: ServerStatus = .stopped
    @Published var apiKey: String = ""
    @Published var port: Int = 8080
    @Published var startAtLogin: Bool = false
    @Published var logs: [LogEntry] = []

    // Cloudflare Tunnel
    @Published var tunnelStatus: TunnelStatus = .stopped
    @Published var cloudflaredInfo: CloudflaredInfo?

    let serverManager = ServerManager()
    let cloudflaredManager = CloudflaredManager()

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
        setupTunnelStatusHandler()

        // Check cloudflared installation and auto-start server if enabled
        Task {
            await checkCloudflaredInstallation()

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

    // MARK: - Cloudflare Tunnel

    func setupTunnelStatusHandler() {
        Task {
            await cloudflaredManager.onStatusChange { [weak self] status in
                Task { @MainActor in
                    self?.tunnelStatus = status
                }
            }
        }
    }

    func checkCloudflaredInstallation() async {
        let isInstalled = await cloudflaredManager.isInstalled()
        if isInstalled {
            cloudflaredInfo = await cloudflaredManager.getInfo()
            tunnelStatus = .stopped
        } else {
            tunnelStatus = .notInstalled
            cloudflaredInfo = nil
        }
    }

    func installCloudflared() async throws {
        addLog(level: .info, message: "Installing cloudflared...")
        try await cloudflaredManager.install()
        cloudflaredInfo = await cloudflaredManager.getInfo()
        tunnelStatus = .stopped
        addLog(level: .info, message: "cloudflared installed successfully")
    }

    func startTunnel() async throws {
        guard serverStatus.isRunning else {
            throw CloudflaredError.failedToStart("Server must be running first")
        }
        addLog(level: .info, message: "Starting Cloudflare Tunnel...")
        let url = try await cloudflaredManager.startQuickTunnel(port: port)
        addLog(level: .info, message: "Tunnel started: \(url)")
    }

    func stopTunnel() async {
        addLog(level: .info, message: "Stopping Cloudflare Tunnel...")
        await cloudflaredManager.stopTunnel()
        addLog(level: .info, message: "Tunnel stopped")
    }

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
    }

    func saveSettings() {
        // Save API key to Keychain
        try? keychainManager.saveAPIKey(apiKey)

        // Save other settings to UserDefaults
        UserDefaults.standard.set(port, forKey: "serverPort")
        UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")

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
                addLog(level: .warning, message: "Failed to update login item: \(error.localizedDescription)")
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
