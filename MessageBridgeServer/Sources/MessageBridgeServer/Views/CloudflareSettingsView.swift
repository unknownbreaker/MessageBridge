import SwiftUI
import MessageBridgeCore

struct CloudflareSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isInstalling = false
    @State private var isStartingTunnel = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // Installation Status Section
            Section {
                HStack {
                    Text("cloudflared:")
                    Spacer()
                    if let info = appState.cloudflaredInfo {
                        VStack(alignment: .trailing) {
                            Text("Installed")
                                .foregroundStyle(.green)
                            if let version = info.version {
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

                if appState.cloudflaredInfo == nil {
                    Button {
                        installCloudflared()
                    } label: {
                        HStack {
                            if isInstalling {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                Text("Installing...")
                            } else {
                                Label("Install cloudflared", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                    .disabled(isInstalling)
                }
            } header: {
                Text("Binary")
            } footer: {
                if appState.cloudflaredInfo == nil {
                    Text("Downloads cloudflared from GitHub releases. No sudo required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Text(appState.tunnelStatus.displayText)
                        .foregroundStyle(.secondary)
                }

                if case .running(let url, _) = appState.tunnelStatus {
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
                if appState.cloudflaredInfo != nil {
                    if appState.tunnelStatus.isRunning {
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
                                    Label("Start Quick Tunnel", systemImage: "play.circle")
                                }
                            }
                        }
                        .disabled(isStartingTunnel || !appState.serverStatus.isRunning)
                    }
                }
            } header: {
                Text("Tunnel")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !appState.serverStatus.isRunning && appState.cloudflaredInfo != nil {
                        Text("Start the server first to enable tunnel.")
                            .foregroundStyle(.orange)
                    }
                    Text("Quick Tunnel creates a temporary public URL. No account required.")
                        .foregroundStyle(.secondary)
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
    }

    var tunnelStatusColor: Color {
        switch appState.tunnelStatus {
        case .notInstalled: return .secondary
        case .stopped: return .secondary
        case .starting: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }

    private func installCloudflared() {
        isInstalling = true
        errorMessage = nil

        Task {
            do {
                try await appState.installCloudflared()
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
                try await appState.startTunnel()
            } catch {
                errorMessage = error.localizedDescription
            }
            isStartingTunnel = false
        }
    }

    private func stopTunnel() {
        Task {
            await appState.stopTunnel()
        }
    }
}

#Preview {
    CloudflareSettingsView()
        .environmentObject(AppState())
}
