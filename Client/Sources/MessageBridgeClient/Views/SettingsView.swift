import AppKit
import Combine
import MessageBridgeClientCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var viewModel: MessagesViewModel

  var body: some View {
    TabView {
      ConnectionSettingsView()
        .environmentObject(viewModel)
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
  @EnvironmentObject var viewModel: MessagesViewModel
  @State private var serverURLString: String = ""
  @State private var apiKey: String = ""
  @State private var showingAPIKey = false
  @State private var saveStatus: String?

  // Original values to track changes
  @State private var originalServerURLString: String = ""
  @State private var originalApiKey: String = ""

  private let keychainManager = KeychainManager()

  private var isConnected: Bool {
    viewModel.connectionStatus == .connected
  }

  private var isConnecting: Bool {
    viewModel.connectionStatus == .connecting
  }

  private var connectionStatusColor: Color {
    switch viewModel.connectionStatus {
    case .connected:
      return .green
    case .connecting:
      return .yellow
    case .disconnected:
      return .red
    }
  }

  private var connectionStatusText: String {
    switch viewModel.connectionStatus {
    case .connected:
      return "Connected"
    case .connecting:
      return "Connecting..."
    case .disconnected:
      return "Disconnected"
    }
  }

  private var hasChanges: Bool {
    serverURLString != originalServerURLString || apiKey != originalApiKey
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
        HStack(spacing: 8) {
          // Connection status indicator
          Circle()
            .fill(connectionStatusColor)
            .frame(width: 8, height: 8)
          Text(connectionStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)

          if let status = saveStatus {
            Text("•")
              .foregroundStyle(.secondary)
            Text(status)
              .font(.caption)
              .foregroundStyle(status.contains("Error") ? .red : .green)
          }

          Spacer()

          if isConnected {
            Button("Disconnect") {
              Task {
                await viewModel.disconnect()
              }
            }
            .help("Disconnect from server")
          } else {
            Button("Connect") {
              Task {
                await viewModel.reconnect()
              }
            }
            .disabled(isConnecting || serverURLString.isEmpty || apiKey.isEmpty)
            .help("Connect to server")
          }

          Button("Save") {
            saveSettings()
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canSave)
        }
      }
    }
    .padding()
    .selectAllOnFocus()
    .onAppear {
      loadSettings()
    }
  }

  private func loadSettings() {
    if let config = try? keychainManager.retrieveServerConfig() {
      serverURLString = config.serverURL.absoluteString
      apiKey = config.apiKey

      // Store original values to track changes
      originalServerURLString = serverURLString
      originalApiKey = apiKey
    }
  }

  private func saveSettings() {
    guard let url = URL(string: serverURLString) else {
      saveStatus = "Error: Invalid URL"
      return
    }

    let config = ServerConfig(serverURL: url, apiKey: apiKey, e2eEnabled: true)
    do {
      try keychainManager.saveServerConfig(config)
      saveStatus = "Saved"

      // Update original values so button disables
      originalServerURLString = serverURLString
      originalApiKey = apiKey

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

// MARK: - Select All on Focus

extension View {
  /// Selects all text in the focused text field when editing begins.
  func selectAllOnFocus() -> some View {
    onReceive(
      NotificationCenter.default.publisher(for: NSTextField.textDidBeginEditingNotification)
    ) {
      notification in
      if let textField = notification.object as? NSTextField {
        // Delay to let SwiftUI finish setting up the field editor
        DispatchQueue.main.async {
          textField.currentEditor()?.selectAll(nil)
        }
      }
    }
  }
}

#Preview {
  SettingsView()
    .environmentObject(MessagesViewModel())
}
