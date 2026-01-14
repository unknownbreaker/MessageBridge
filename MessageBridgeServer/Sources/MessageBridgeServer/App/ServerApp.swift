import SwiftUI
import AppKit
import MessageBridgeCore
import ServiceManagement

// App delegate to handle lifecycle events like termination
class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up any running tunnels when app quits
        guard let appState = appState else { return }

        // Use a semaphore to wait for async cleanup to complete
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            // Stop ngrok tunnel if running
            if appState.ngrokTunnelStatus.isRunning {
                await appState.stopNgrokTunnel()
            }

            // Stop cloudflare tunnel if running
            if appState.cloudfareTunnelStatus.isRunning {
                await appState.stopCloudfareTunnel()
            }

            semaphore.signal()
        }

        // Wait up to 2 seconds for cleanup
        _ = semaphore.wait(timeout: .now() + 2)
    }
}

// Window manager to handle opening windows from menu bar
class WindowManager: ObservableObject {
    static let shared = WindowManager()

    var settingsWindow: NSWindow?
    var logsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var permissionsWindow: NSWindow?
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

    func openPermissions(onDismiss: @escaping () -> Void = {}) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = permissionsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Create a binding that closes the window when set to false
        class BindingHolder {
            var onDismiss: () -> Void = {}
        }
        let holder = BindingHolder()
        holder.onDismiss = onDismiss

        let isPresented = Binding<Bool>(
            get: { true },
            set: { [weak self] newValue in
                if !newValue {
                    self?.permissionsWindow?.close()
                    self?.permissionsWindow = nil
                    holder.onDismiss()
                }
            }
        )

        let permissionsView = PermissionsView(isPresented: isPresented)
        let hostingController = NSHostingController(rootView: permissionsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Permissions Required"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.permissionsWindow = window
    }
}

@main
struct ServerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    init() {
        // WindowManager.shared.appState will be set when menu appears
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appState: appState)
                .onAppear {
                    // Set appState reference for cleanup on termination
                    appDelegate.appState = appState
                }
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

        Button("Permissions...") {
            debugLog("Permissions clicked")
            WindowManager.shared.appState = appState
            WindowManager.shared.openPermissions()
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

    // Auto-update settings
    @Published var cloudflaredAutoUpdate: Bool = false
    @Published var ngrokAutoUpdate: Bool = false
    @Published var cloudflaredUpdateAvailable: String? = nil
    @Published var ngrokUpdateAvailable: String? = nil
    @Published var isCheckingForUpdates: Bool = false

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
        setupCoreLogging()

        // Check permissions and tunnel installations on startup
        Task { @MainActor in
            // Check if all permissions are granted
            let permissionsManager = PermissionsManager.shared
            let allGranted = await permissionsManager.allPermissionsGranted()

            if !allGranted {
                // Show permissions window if any permission is missing
                WindowManager.shared.appState = self
                WindowManager.shared.openPermissions()
            }

            // Check tunnel binary installations
            await checkTunnelInstallations()

            // Auto-start server if enabled
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

    // MARK: - Core Logging

    private func setupCoreLogging() {
        // Subscribe to logs from MessageBridgeCore
        ServerLogger.shared.subscribe { [weak self] entry in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let level: LogLevel
                switch entry.level {
                case .debug: level = .debug
                case .info: level = .info
                case .warning: level = .warning
                case .error: level = .error
                }
                let logEntry = LogEntry(
                    level: level,
                    message: entry.message,
                    file: entry.file,
                    function: entry.function,
                    line: entry.line
                )
                self.logs.insert(logEntry, at: 0)
                if self.logs.count > 1000 {
                    self.logs = Array(self.logs.prefix(1000))
                }
            }
        }
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
            // Check if there's an existing cloudflared process running
            let externalProcessDetected = await cloudflaredManager.detectExistingTunnel()
            if !externalProcessDetected {
                cloudfareTunnelStatus = .stopped
            }
            // If external process detected, status is already set by detectExistingTunnel()
        } else {
            cloudfareTunnelStatus = .notInstalled
            cloudflaredInfo = nil
        }

        // Check ngrok
        let ngrokInstalled = await ngrokManager.isInstalled()
        if ngrokInstalled {
            ngrokInfo = await ngrokManager.getInfo()
            // Check if there's an existing ngrok process running and try to get its URL
            if let url = await ngrokManager.detectExistingTunnel() {
                addLog(level: .info, message: "Detected existing ngrok tunnel: \(url)")
            } else {
                ngrokTunnelStatus = .stopped
            }
            // If external process detected, status is already set by detectExistingTunnel()
        } else {
            ngrokTunnelStatus = .notInstalled
            ngrokInfo = nil
        }
    }

    /// Refresh tunnel status - can be called when the settings view appears
    func refreshTunnelStatus() async {
        await checkTunnelInstallations()
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

    // MARK: - Update Checking

    func checkForUpdates() async {
        isCheckingForUpdates = true
        addLog(level: .info, message: "Checking for tunnel software updates...")

        // Check cloudflared updates
        if cloudflaredInfo != nil {
            if let latestVersion = await cloudflaredManager.getLatestVersion() {
                if let currentVersion = cloudflaredInfo?.version,
                   isNewerVersion(latestVersion, than: currentVersion) {
                    cloudflaredUpdateAvailable = latestVersion
                    addLog(level: .info, message: "cloudflared update available: \(latestVersion)")
                } else {
                    cloudflaredUpdateAvailable = nil
                    addLog(level: .debug, message: "cloudflared is up to date")
                }
            }
        }

        // Check ngrok updates
        if ngrokInfo != nil {
            if let latestVersion = await ngrokManager.getLatestVersion() {
                if let currentVersion = ngrokInfo?.version,
                   isNewerVersion(latestVersion, than: currentVersion) {
                    ngrokUpdateAvailable = latestVersion
                    addLog(level: .info, message: "ngrok update available: \(latestVersion)")
                } else {
                    ngrokUpdateAvailable = nil
                    addLog(level: .debug, message: "ngrok is up to date")
                }
            }
        }

        isCheckingForUpdates = false
    }

    func updateCloudflared() async throws {
        addLog(level: .info, message: "Updating cloudflared...")

        // Stop tunnel if running
        if cloudfareTunnelStatus.isRunning {
            await stopCloudfareTunnel()
        }

        try await cloudflaredManager.install()
        cloudflaredInfo = await cloudflaredManager.getInfo()
        cloudflaredUpdateAvailable = nil
        addLog(level: .info, message: "cloudflared updated successfully")
    }

    func updateNgrok() async throws {
        addLog(level: .info, message: "Updating ngrok...")

        // Stop tunnel if running
        if ngrokTunnelStatus.isRunning {
            await stopNgrokTunnel()
        }

        try await ngrokManager.install()
        ngrokInfo = await ngrokManager.getInfo()
        ngrokUpdateAvailable = nil
        addLog(level: .info, message: "ngrok updated successfully")
    }

    /// Compare version strings (simple semantic versioning comparison)
    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(newParts.count, currentParts.count) {
            let newVal = i < newParts.count ? newParts[i] : 0
            let currentVal = i < currentParts.count ? currentParts[i] : 0

            if newVal > currentVal { return true }
            if newVal < currentVal { return false }
        }

        return false
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

        // Load auto-update settings
        cloudflaredAutoUpdate = UserDefaults.standard.bool(forKey: "cloudflaredAutoUpdate")
        ngrokAutoUpdate = UserDefaults.standard.bool(forKey: "ngrokAutoUpdate")
    }

    func saveSettings() {
        // Save API key to Keychain
        try? keychainManager.saveAPIKey(apiKey)

        // Save other settings to UserDefaults
        UserDefaults.standard.set(port, forKey: "serverPort")
        UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
        UserDefaults.standard.set(debugLoggingEnabled, forKey: "debugLoggingEnabled")
        UserDefaults.standard.set(selectedTunnelProvider.rawValue, forKey: "tunnelProvider")
        UserDefaults.standard.set(cloudflaredAutoUpdate, forKey: "cloudflaredAutoUpdate")
        UserDefaults.standard.set(ngrokAutoUpdate, forKey: "ngrokAutoUpdate")

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
