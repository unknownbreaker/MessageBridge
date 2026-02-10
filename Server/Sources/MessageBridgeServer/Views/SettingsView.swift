import MessageBridgeCore
import SwiftUI

enum SettingsTab: Hashable {
  case general
  case security
  case tunnel
}

struct SettingsView: View {
  @EnvironmentObject var appState: AppState
  @State private var portText: String = ""
  @State private var showRegenerateConfirmation = false
  @State private var selectedTab: SettingsTab

  /// If true, auto-show the auth token input field when tunnel tab appears
  let showAuthTokenField: Bool

  init(initialTab: SettingsTab = .general, showAuthTokenField: Bool = false) {
    _selectedTab = State(initialValue: initialTab)
    self.showAuthTokenField = showAuthTokenField
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      GeneralSettingsView(
        portText: $portText, showRegenerateConfirmation: $showRegenerateConfirmation
      )
      .environmentObject(appState)
      .tabItem {
        Label("General", systemImage: "gear")
      }
      .tag(SettingsTab.general)

      SecuritySettingsView(showRegenerateConfirmation: $showRegenerateConfirmation)
        .environmentObject(appState)
        .tabItem {
          Label("Security", systemImage: "lock")
        }
        .tag(SettingsTab.security)

      TunnelSettingsView(autoShowTokenField: showAuthTokenField)
        .environmentObject(appState)
        .tabItem {
          Label("Tunnel", systemImage: "network")
        }
        .tag(SettingsTab.tunnel)
    }
    .frame(width: 450, height: 350)
    .onAppear {
      portText = String(appState.port)
    }
  }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
  @EnvironmentObject var appState: AppState
  @Binding var portText: String
  @Binding var showRegenerateConfirmation: Bool

  var body: some View {
    Form {
      Section {
        HStack {
          Text("Port:")
          TextField("8080", text: $portText)
            .frame(width: 80)
            .onChange(of: portText) { _, newValue in
              if let port = Int(newValue), port > 0, port < 65536 {
                appState.port = port
                appState.saveSettings()
              }
            }
        }

        Toggle("Start at Login", isOn: $appState.startAtLogin)
          .onChange(of: appState.startAtLogin) { _, _ in
            appState.saveSettings()
          }
      } header: {
        Text("Server")
      }

      Section {
        Toggle("Enable Debug Logging", isOn: $appState.debugLoggingEnabled)
          .onChange(of: appState.debugLoggingEnabled) { _, _ in
            appState.saveSettings()
          }
      } header: {
        Text("Developer")
      } footer: {
        Text("When enabled, detailed debug logs are written to /tmp/messagebridge-debug.log")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        HStack {
          Text("Status:")
          Spacer()
          Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
          Text(appState.serverStatus.displayText)
            .foregroundStyle(.secondary)
        }

        if appState.serverStatus.isRunning {
          Button("Restart Server") {
            Task {
              await appState.restartServer()
            }
          }
        }
      } header: {
        Text("Status")
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  var statusColor: Color {
    switch appState.serverStatus {
    case .stopped: return .secondary
    case .starting: return .yellow
    case .running: return .green
    case .error: return .red
    }
  }
}

// MARK: - Security Settings

struct SecuritySettingsView: View {
  @EnvironmentObject var appState: AppState
  @Binding var showRegenerateConfirmation: Bool
  @State private var isRevealed = false

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text("API Key")
            .font(.headline)

          HStack {
            if isRevealed {
              Text(appState.apiKey)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            } else {
              Text(String(repeating: "•", count: 32))
                .font(.system(.body, design: .monospaced))
            }

            Spacer()
          }

          HStack {
            Button {
              isRevealed.toggle()
            } label: {
              Label(isRevealed ? "Hide" : "Reveal", systemImage: isRevealed ? "eye.slash" : "eye")
            }

            Button {
              appState.copyAPIKey()
            } label: {
              Label("Copy", systemImage: "doc.on.doc")
            }

            Spacer()

            Button(role: .destructive) {
              showRegenerateConfirmation = true
            } label: {
              Label("Regenerate", systemImage: "arrow.clockwise")
            }
          }
        }
      } footer: {
        Text(
          "The API key is required for clients to connect. Keep it secure and share only with trusted devices."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
    .alert("Regenerate API Key?", isPresented: $showRegenerateConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Regenerate", role: .destructive) {
        appState.generateNewAPIKey()
      }
    } message: {
      Text(
        "This will invalidate the current API key. All connected clients will need to be updated with the new key."
      )
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

      Text("MessageBridge Server")
        .font(.title)
        .fontWeight(.semibold)

      Text("Version \(versionString)")
        .foregroundStyle(.secondary)

      Text("A self-hosted iMessage bridge for accessing your messages on any Mac.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(.horizontal)

      Spacer()

      Link(
        "View on GitHub",
        destination: URL(string: "https://github.com/unknownbreaker/MessageBridge")!
      )
      .font(.caption)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  SettingsView(initialTab: .general)
    .environmentObject(AppState())
}
