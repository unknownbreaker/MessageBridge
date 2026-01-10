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
    @State private var e2eEnabled: Bool = false
    @State private var showingAPIKey = false
    @State private var saveStatus: String?

    // Original values to track changes
    @State private var originalServerURLString: String = ""
    @State private var originalApiKey: String = ""
    @State private var originalE2eEnabled: Bool = false

    private let keychainManager = KeychainManager()

    private var hasChanges: Bool {
        serverURLString != originalServerURLString ||
        apiKey != originalApiKey ||
        e2eEnabled != originalE2eEnabled
    }

    private var canSave: Bool {
        hasChanges && !serverURLString.isEmpty && !apiKey.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $serverURLString, prompt: Text("http://100.x.y.z:8080"))
                    .textFieldStyle(.roundedBorder)
                    .help("Enter your server URL (e.g., http://100.x.y.z:8080 or https://tunnel.example.com)")

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
                Toggle("End-to-End Encryption", isOn: $e2eEnabled)
                    .help("Encrypt all data so relay servers cannot read your messages")

                if e2eEnabled {
                    Text("Messages will be encrypted using your API key before leaving your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Security")
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
                    .disabled(!canSave)
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
            e2eEnabled = config.e2eEnabled

            // Store original values to track changes
            originalServerURLString = serverURLString
            originalApiKey = apiKey
            originalE2eEnabled = e2eEnabled
        }
    }

    private func saveSettings() {
        guard let url = URL(string: serverURLString) else {
            saveStatus = "Error: Invalid URL"
            return
        }

        let config = ServerConfig(serverURL: url, apiKey: apiKey, e2eEnabled: e2eEnabled)
        do {
            try keychainManager.saveServerConfig(config)
            saveStatus = "Saved"

            // Update original values so button disables
            originalServerURLString = serverURLString
            originalApiKey = apiKey
            originalE2eEnabled = e2eEnabled

            // Clear status after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = nil
            }
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
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

            Text("Access your iMessages from any Mac.")
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
