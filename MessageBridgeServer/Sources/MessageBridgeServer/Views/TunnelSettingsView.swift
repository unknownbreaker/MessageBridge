import MessageBridgeCore
import SwiftUI

struct TunnelSettingsView: View {
  @EnvironmentObject var appState: AppState
  @State private var isInstalling = false
  @State private var isStartingTunnel = false
  @State private var isUpdating = false
  @State private var errorMessage: String?
  @State private var ngrokAuthToken = ""
  @State private var isSavingToken = false
  @State private var showTokenField = false

  var body: some View {
    Form {
      // Provider Selection
      Section {
        Picker("Provider", selection: $appState.selectedTunnelProvider) {
          ForEach(TunnelProviderType.allCases, id: \.self) { provider in
            HStack {
              Image(systemName: provider.iconName)
              Text(provider.displayName)
            }
            .tag(provider)
          }
        }
        .onChange(of: appState.selectedTunnelProvider) { _, _ in
          appState.saveSettings()
        }
      } header: {
        Text("Tunnel Provider")
      } footer: {
        Text(appState.selectedTunnelProvider.description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Installation Status Section
      Section {
        HStack {
          Text(binaryName + ":")
          Spacer()
          if isInstalled {
            VStack(alignment: .trailing) {
              Text("Installed")
                .foregroundStyle(.green)
              if let version = installedVersion {
                Text("v\(version)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          } else {
            Text("Not Installed")
              .foregroundStyle(.secondary)
          }
        }

        if !isInstalled {
          Button {
            installBinary()
          } label: {
            HStack {
              if isInstalling {
                ProgressView()
                  .scaleEffect(0.7)
                  .frame(width: 16, height: 16)
                Text("Installing...")
              } else {
                Label("Install \(binaryName)", systemImage: "arrow.down.circle")
              }
            }
          }
          .disabled(isInstalling)
        }
      } header: {
        Text("Binary")
      } footer: {
        if !isInstalled {
          Text("Downloads \(binaryName) automatically. No sudo required.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // ngrok Auth Token Section (only shown when ngrok is selected and installed)
      if appState.selectedTunnelProvider == .ngrok && isInstalled {
        Section {
          if appState.ngrokAuthTokenConfigured && !showTokenField {
            HStack {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
              Text("Authtoken configured")
              Spacer()
              Button("Change") {
                showTokenField = true
              }
              Button("Remove", role: .destructive) {
                Task {
                  await appState.removeNgrokAuthToken()
                }
              }
            }
          } else {
            if !appState.ngrokAuthTokenConfigured {
              HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.yellow)
                Text("ngrok requires a free account to create tunnels.")
                  .font(.callout)
              }

              Text(
                "[Sign up at dashboard.ngrok.com/signup](https://dashboard.ngrok.com/signup) to get your authtoken."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }

            SecureField("Paste authtoken here", text: $ngrokAuthToken)
              .textFieldStyle(.roundedBorder)

            HStack {
              Button {
                saveAuthToken()
              } label: {
                HStack {
                  if isSavingToken {
                    ProgressView()
                      .scaleEffect(0.7)
                      .frame(width: 16, height: 16)
                    Text("Saving...")
                  } else {
                    Text("Save Token")
                  }
                }
              }
              .disabled(ngrokAuthToken.isEmpty || isSavingToken)

              if showTokenField {
                Button("Cancel") {
                  showTokenField = false
                  ngrokAuthToken = ""
                }
              }
            }
          }
        } header: {
          Text("Authentication")
        } footer: {
          Text("Your authtoken is stored securely in Keychain.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // Updates Section (only shown when binary is installed)
      if isInstalled {
        Section {
          Toggle("Auto-check for updates", isOn: autoUpdateBinding)
            .onChange(of: autoUpdateBinding.wrappedValue) { _, _ in
              appState.saveSettings()
            }

          HStack {
            Button {
              checkForUpdates()
            } label: {
              HStack {
                if appState.isCheckingForUpdates {
                  ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                  Text("Checking...")
                } else {
                  Label("Check for Updates", systemImage: "arrow.clockwise")
                }
              }
            }
            .disabled(appState.isCheckingForUpdates)

            Spacer()

            if let updateVersion = updateAvailable {
              Text("v\(updateVersion) available")
                .font(.caption)
                .foregroundStyle(.blue)
            }
          }

          if updateAvailable != nil {
            Button {
              updateBinary()
            } label: {
              HStack {
                if isUpdating {
                  ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                  Text("Updating...")
                } else {
                  Label("Update \(binaryName)", systemImage: "arrow.down.circle.fill")
                }
              }
            }
            .disabled(isUpdating || currentTunnelStatus.isRunning)
          }
        } header: {
          Text("Updates")
        } footer: {
          VStack(alignment: .leading, spacing: 4) {
            if appState.selectedTunnelProvider == .ngrok {
              Text(
                "Note: ngrok version checking is not available. Use \"Check for Updates\" to reinstall the latest version."
              )
              .foregroundStyle(.secondary)
            }
            if currentTunnelStatus.isRunning && updateAvailable != nil {
              Text("Stop the tunnel before updating.")
                .foregroundStyle(.orange)
            }
          }
          .font(.caption)
        }
      }

      // Tunnel Status Section
      Section {
        HStack {
          Text("Status:")
          Spacer()
          Circle()
            .fill(tunnelStatusColor)
            .frame(width: 8, height: 8)
          Text(currentTunnelStatus.displayText)
            .foregroundStyle(.secondary)
        }

        if case .running(let url, _) = currentTunnelStatus {
          HStack {
            Text("URL:")
            Spacer()
            Text(url)
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
              .lineLimit(1)
              .truncationMode(.middle)
          }

          Button {
            appState.copyTunnelURL()
          } label: {
            Label("Copy URL", systemImage: "doc.on.doc")
          }
        }

        // Tunnel Controls
        if isInstalled {
          if currentTunnelStatus.isRunning {
            Button(role: .destructive) {
              stopTunnel()
            } label: {
              Label("Stop Tunnel", systemImage: "stop.circle")
            }
          } else {
            Button {
              startTunnel()
            } label: {
              HStack {
                if isStartingTunnel {
                  ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                  Text("Starting...")
                } else {
                  Label("Start Tunnel", systemImage: "play.circle")
                }
              }
            }
            .disabled(isStartingTunnel || !appState.serverStatus.isRunning || !canStartTunnel)
          }
        }
      } header: {
        Text("Tunnel")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          if !appState.serverStatus.isRunning && isInstalled {
            Text("Start the server first to enable tunnel.")
              .foregroundStyle(.orange)
          }
          if appState.selectedTunnelProvider == .ngrok && !appState.ngrokAuthTokenConfigured {
            Text("Configure your authtoken above to enable tunnel.")
              .foregroundStyle(.orange)
          } else if appState.selectedTunnelProvider == .ngrok {
            Text(
              "ngrok free tier provides temporary URLs that change on each restart."
            )
            .foregroundStyle(.secondary)
          } else {
            Text("Quick Tunnel creates a temporary public URL. No account required.")
              .foregroundStyle(.secondary)
          }
        }
        .font(.caption)
      }

      // Error Message
      if let error = errorMessage {
        Section {
          Text(error)
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      // Refresh tunnel status when view appears to detect externally running tunnels
      Task {
        await appState.refreshTunnelStatus()
      }
    }
  }

  // MARK: - Computed Properties

  private var binaryName: String {
    switch appState.selectedTunnelProvider {
    case .cloudflare: return "cloudflared"
    case .ngrok: return "ngrok"
    }
  }

  private var isInstalled: Bool {
    switch appState.selectedTunnelProvider {
    case .cloudflare: return appState.cloudflaredInfo != nil
    case .ngrok: return appState.ngrokInfo != nil
    }
  }

  private var installedVersion: String? {
    switch appState.selectedTunnelProvider {
    case .cloudflare: return appState.cloudflaredInfo?.version
    case .ngrok: return appState.ngrokInfo?.version
    }
  }

  private var autoUpdateBinding: Binding<Bool> {
    switch appState.selectedTunnelProvider {
    case .cloudflare:
      return $appState.cloudflaredAutoUpdate
    case .ngrok:
      return $appState.ngrokAutoUpdate
    }
  }

  private var updateAvailable: String? {
    switch appState.selectedTunnelProvider {
    case .cloudflare: return appState.cloudflaredUpdateAvailable
    case .ngrok: return appState.ngrokUpdateAvailable
    }
  }

  private var currentTunnelStatus: TunnelStatus {
    switch appState.selectedTunnelProvider {
    case .cloudflare: return appState.cloudfareTunnelStatus
    case .ngrok: return appState.ngrokTunnelStatus
    }
  }

  private var canStartTunnel: Bool {
    switch appState.selectedTunnelProvider {
    case .cloudflare: return true
    case .ngrok: return appState.ngrokAuthTokenConfigured
    }
  }

  private var tunnelStatusColor: Color {
    switch currentTunnelStatus {
    case .notInstalled: return .secondary
    case .stopped: return .secondary
    case .starting: return .yellow
    case .running: return .green
    case .error: return .red
    }
  }

  // MARK: - Actions

  private func installBinary() {
    isInstalling = true
    errorMessage = nil

    Task {
      do {
        switch appState.selectedTunnelProvider {
        case .cloudflare:
          try await appState.installCloudflared()
        case .ngrok:
          try await appState.installNgrok()
        }
      } catch {
        errorMessage = error.localizedDescription
      }
      isInstalling = false
    }
  }

  private func startTunnel() {
    isStartingTunnel = true
    errorMessage = nil

    Task {
      do {
        switch appState.selectedTunnelProvider {
        case .cloudflare:
          try await appState.startCloudfareTunnel()
        case .ngrok:
          try await appState.startNgrokTunnel()
        }
      } catch {
        errorMessage = error.localizedDescription
      }
      isStartingTunnel = false
    }
  }

  private func stopTunnel() {
    Task {
      switch appState.selectedTunnelProvider {
      case .cloudflare:
        await appState.stopCloudfareTunnel()
      case .ngrok:
        await appState.stopNgrokTunnel()
      }
    }
  }

  private func checkForUpdates() {
    errorMessage = nil
    Task {
      await appState.checkForUpdates()
    }
  }

  private func saveAuthToken() {
    isSavingToken = true
    errorMessage = nil

    Task {
      do {
        try await appState.saveNgrokAuthToken(ngrokAuthToken)
        ngrokAuthToken = ""
        showTokenField = false
      } catch {
        errorMessage = error.localizedDescription
      }
      isSavingToken = false
    }
  }

  private func updateBinary() {
    isUpdating = true
    errorMessage = nil

    Task {
      do {
        switch appState.selectedTunnelProvider {
        case .cloudflare:
          try await appState.updateCloudflared()
        case .ngrok:
          try await appState.updateNgrok()
        }
      } catch {
        errorMessage = error.localizedDescription
      }
      isUpdating = false
    }
  }
}

#Preview {
  TunnelSettingsView()
    .environmentObject(AppState())
}
