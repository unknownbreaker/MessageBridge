import SwiftUI
import AppKit
import MessageBridgeClientCore

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettingsView()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }

            TailscaleSettingsView()
                .tabItem {
                    Label("Tailscale", systemImage: "link")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - Connection Settings

struct ConnectionSettingsView: View {
    @State private var serverURLString: String = ""
    @State private var apiKey: String = ""
    @State private var showingAPIKey = false
    @State private var saveStatus: String?

    private let keychainManager = KeychainManager()

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $serverURLString, prompt: Text("http://100.x.y.z:8080"))
                    .textFieldStyle(.roundedBorder)
                    .help("Enter your home Mac's Tailscale IP address and port")

                HStack {
                    if showingAPIKey {
                        TextField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showingAPIKey.toggle()
                    } label: {
                        Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                .help("API key from your MessageBridge Server")
            } header: {
                Text("Server Connection")
            }

            Section {
                HStack {
                    if let status = saveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("Error") ? .red : .green)
                    }

                    Spacer()

                    Button("Save") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(serverURLString.isEmpty || apiKey.isEmpty)
                }
            }
        }
        .padding()
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        if let config = try? keychainManager.retrieveServerConfig() {
            serverURLString = config.serverURL.absoluteString
            apiKey = config.apiKey
        }
    }

    private func saveSettings() {
        guard let url = URL(string: serverURLString) else {
            saveStatus = "Error: Invalid URL"
            return
        }

        let config = ServerConfig(serverURL: url, apiKey: apiKey)
        do {
            try keychainManager.saveServerConfig(config)
            saveStatus = "Saved"
            // Clear status after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = nil
            }
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Tailscale Settings

struct TailscaleSettingsView: View {
    @State private var tailscaleStatus: TailscaleStatus = .notInstalled
    @State private var devices: [TailscaleDevice] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let tailscaleManager = TailscaleManager()

    var body: some View {
        Form {
            Section {
                HStack {
                    Label {
                        Text("Status")
                    } icon: {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(tailscaleStatus.displayText)
                            .foregroundStyle(.secondary)

                        Button {
                            Task { await refreshStatus() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                    }
                }

                if case .connected(let ip, let hostname) = tailscaleStatus {
                    LabeledContent("IP Address") {
                        HStack {
                            Text(ip)
                                .font(.system(.body, design: .monospaced))
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ip, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("Copy IP address")
                        }
                    }

                    LabeledContent("Hostname") {
                        Text(hostname)
                            .foregroundStyle(.secondary)
                    }
                }

                if case .notInstalled = tailscaleStatus {
                    HStack {
                        Text("Tailscale is required to connect to your server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Download") {
                            Task {
                                let url = await tailscaleManager.getDownloadURL()
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if case .stopped = tailscaleStatus {
                    HStack {
                        Text("Tailscale is installed but not running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Open Tailscale") {
                            Task {
                                await tailscaleManager.openTailscaleApp()
                            }
                        }
                    }
                }
            } header: {
                Text("Tailscale VPN")
            }

            if case .connected = tailscaleStatus, !devices.isEmpty {
                Section {
                    ForEach(devices) { device in
                        HStack {
                            Image(systemName: deviceIcon(for: device))
                                .foregroundStyle(device.online ? .green : .secondary)

                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .fontWeight(device.isSelf ? .semibold : .regular)
                                Text(device.displayIP)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if device.isSelf {
                                Text("This device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if device.online {
                                Text("Online")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Offline")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Tailnet Devices")
                }
            }
        }
        .padding()
        .task {
            await refreshStatus()
            if case .connected = tailscaleStatus {
                await loadDevices()
            }
        }
    }

    private func refreshStatus() async {
        isLoading = true
        tailscaleStatus = await tailscaleManager.getStatus(forceRefresh: true)
        isLoading = false
    }

    private func loadDevices() async {
        do {
            devices = try await tailscaleManager.getDevices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var statusColor: Color {
        switch tailscaleStatus {
        case .notInstalled: return .gray
        case .stopped: return .red
        case .connecting: return .yellow
        case .connected: return .green
        case .error: return .orange
        }
    }

    private func deviceIcon(for device: TailscaleDevice) -> String {
        if let os = device.os?.lowercased() {
            if os.contains("macos") || os.contains("darwin") {
                return "desktopcomputer"
            } else if os.contains("ios") {
                return "iphone"
            } else if os.contains("android") {
                return "phone"
            } else if os.contains("windows") {
                return "pc"
            } else if os.contains("linux") {
                return "server.rack"
            }
        }
        return "network"
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text(appName)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version \(appVersion.description)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Access your iMessages from any Mac using Tailscale VPN.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
