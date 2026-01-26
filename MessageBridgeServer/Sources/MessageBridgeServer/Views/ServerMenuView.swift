import AppKit
import MessageBridgeCore
import SwiftUI

// Debug logging that respects the user's debug setting
func debugLog(
  _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
  // Check if debug logging is enabled
  guard UserDefaults.standard.bool(forKey: "debugLoggingEnabled") else { return }

  let logFile = "/tmp/messagebridge-debug.log"
  let timestamp = ISO8601DateFormatter().string(from: Date())
  let fileName = (file as NSString).lastPathComponent
  let logMessage = "[\(timestamp)] [\(fileName):\(line)] \(function): \(message)\n"

  if let data = logMessage.data(using: .utf8) {
    if FileManager.default.fileExists(atPath: logFile) {
      if let handle = FileHandle(forWritingAtPath: logFile) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
      }
    } else {
      FileManager.default.createFile(atPath: logFile, contents: data)
    }
  }
}

// Note: ServerMenuView is no longer used - we now use native menu in ServerApp.swift
// Keeping this file for reference and supporting views (TailscaleStatusView, CloudflareStatusView, etc.)

struct ServerMenuView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.openWindow) private var openWindow

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

      // Cloudflare Tunnel status
      CloudflareStatusView()
        .environmentObject(appState)
        .padding(.vertical, 8)
        .padding(.horizontal)

      Divider()

      // Menu items
      VStack(alignment: .leading, spacing: 8) {
        Button("View Logs...") {
          debugLog("View Logs button clicked")
          NSApp.activate(ignoringOtherApps: true)
          openWindow(id: "log-viewer")
        }

        Button("Settings...") {
          debugLog("Settings button clicked")
          // Delay to let menu close first
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            debugLog("Opening settings window...")
            NSApp.activate(ignoringOtherApps: true)
            // Try multiple approaches
            if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
              debugLog("showSettingsWindow: succeeded")
            } else if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) {
              debugLog("showPreferencesWindow: succeeded")
            } else {
              debugLog("Both selectors failed, trying keyboard shortcut")
              // Simulate Cmd+, keyboard shortcut
              let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: ",",
                charactersIgnoringModifiers: ",",
                isARepeat: false,
                keyCode: 43
              )
              if let event = event {
                NSApp.sendEvent(event)
              }
            }
          }
        }
      }
      .padding()

      Divider()

      // Quit
      Button("Quit MessageBridge Server") {
        debugLog("Quit clicked")
        Task {
          await appState.stopServer()
          NSApplication.shared.terminate(nil)
        }
      }
      .padding()
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

// MARK: - Cloudflare Status View

struct CloudflareStatusView: View {
  @EnvironmentObject var appState: AppState
  @State private var isStartingTunnel = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Cloudflare Tunnel")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()
      }

      HStack(spacing: 6) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)

        Text(appState.tunnelStatus.displayText)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer()

        if case .notInstalled = appState.tunnelStatus {
          Button("Setup") {
            debugLog("Cloudflare Setup clicked")
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
          }
          .font(.caption)
          .buttonStyle(.bordered)
          .controlSize(.small)
        } else if !appState.tunnelStatus.isRunning {
          Button("Start") {
            startTunnel()
          }
          .font(.caption)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(isStartingTunnel || !appState.serverStatus.isRunning)
        } else {
          Button("Stop") {
            stopTunnel()
          }
          .font(.caption)
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      if case .running(let url, _) = appState.tunnelStatus {
        HStack {
          Text(url)
            .font(.system(.caption2, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)

          Button {
            appState.copyTunnelURL()
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.caption2)
          }
          .buttonStyle(.plain)
          .help("Copy tunnel URL")
        }
      }
    }
  }

  private var statusColor: Color {
    switch appState.tunnelStatus {
    case .notInstalled: return .gray
    case .stopped: return .secondary
    case .starting: return .yellow
    case .running: return .green
    case .error: return .orange
    }
  }

  private func startTunnel() {
    isStartingTunnel = true
    Task {
      do {
        try await appState.startTunnel()
      } catch {
        // Error is logged in AppState
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
  ServerMenuView()
    .environmentObject(AppState())
}
