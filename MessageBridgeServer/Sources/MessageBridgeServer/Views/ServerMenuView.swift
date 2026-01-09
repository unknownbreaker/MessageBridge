import SwiftUI
import AppKit
import MessageBridgeCore

struct ServerMenuView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with status
            HeaderView(status: appState.serverStatus)
                .padding()

            Divider()

            // Server controls
            ServerControlsView()
                .environmentObject(appState)
                .padding(.vertical, 8)
                .padding(.horizontal)

            Divider()

            // API Key section
            APIKeyView()
                .environmentObject(appState)
                .padding(.vertical, 8)
                .padding(.horizontal)

            Divider()

            // Tailscale status
            TailscaleStatusView()
                .environmentObject(appState)
                .padding(.vertical, 8)
                .padding(.horizontal)

            Divider()

            // Menu items
            VStack(alignment: .leading, spacing: 4) {
                MenuButton(title: "View Logs...", icon: "doc.text") {
                    openWindow(id: "log-viewer")
                }

                MenuButton(title: "Settings...", icon: "gear") {
                    openSettings()
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)

            Divider()

            // Quit
            MenuButton(title: "Quit MessageBridge Server", icon: "power") {
                Task {
                    await appState.stopServer()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
        }
        .frame(width: 300)
    }
}

// MARK: - Header View

struct HeaderView: View {
    let status: ServerStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MessageBridge Server")
                    .font(.headline)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(status.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(statusColor)
        }
    }

    var statusColor: Color {
        switch status {
        case .stopped: return .secondary
        case .starting: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }
}

// MARK: - Server Controls

struct ServerControlsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Port:")
                    .foregroundStyle(.secondary)
                Text("\(appState.port)")
                    .fontWeight(.medium)
            }
            .font(.caption)

            HStack(spacing: 8) {
                if appState.serverStatus.isRunning {
                    Button("Stop") {
                        Task {
                            await appState.stopServer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("Restart") {
                        Task {
                            await appState.restartServer()
                        }
                    }
                } else {
                    Button("Start Server") {
                        Task {
                            await appState.startServer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.apiKey.isEmpty)
                }
            }
        }
    }
}

// MARK: - API Key View

struct APIKeyView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if isRevealed {
                    Text(appState.apiKey)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(String(repeating: "•", count: 16))
                        .font(.system(.caption, design: .monospaced))
                }

                Spacer()

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    appState.copyAPIKey()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
    }
}

// MARK: - Menu Button

struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

// MARK: - Tailscale Status View

struct TailscaleStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var tailscaleStatus: TailscaleStatus = .notInstalled
    @State private var isLoading = true

    private let tailscaleManager = TailscaleManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tailscale")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Button {
                        Task {
                            await refreshStatus()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh status")
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(tailscaleStatus.displayText)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if case .notInstalled = tailscaleStatus {
                    Button("Install") {
                        Task {
                            let url = await tailscaleManager.getDownloadURL()
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if case .stopped = tailscaleStatus {
                    Button("Open") {
                        Task {
                            await tailscaleManager.openTailscaleApp()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if case .connected(let ip, _) = tailscaleStatus {
                HStack {
                    Text("IP:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(ip)
                        .font(.system(.caption2, design: .monospaced))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ip, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Copy IP address")
                }
            }
        }
        .task {
            await refreshStatus()
        }
    }

    private func refreshStatus() async {
        isLoading = true
        tailscaleStatus = await tailscaleManager.getStatus(forceRefresh: true)
        isLoading = false
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
}

#Preview {
    ServerMenuView()
        .environmentObject(AppState())
}
