import MessageBridgeClientCore
import SwiftUI

struct LogViewerView: View {
  @State private var logs: [LogEntry] = []
  @State private var selectedLevel: LogLevel? = nil
  @State private var isLoading = false
  @State private var searchText = ""

  var body: some View {
    VStack(spacing: 0) {
      // Toolbar
      HStack {
        Picker("Level", selection: $selectedLevel) {
          Text("All Levels").tag(nil as LogLevel?)
          ForEach(LogLevel.allCases, id: \.self) { level in
            Text("\(level.emoji) \(level.label)").tag(level as LogLevel?)
          }
        }
        .pickerStyle(.menu)
        .frame(width: 150)

        TextField("Search logs...", text: $searchText)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 300)

        Spacer()

        Button("Refresh") {
          Task {
            await loadLogs()
          }
        }

        Button("Clear Logs") {
          Task {
            await AppLogger.shared.clearLogs()
            await loadLogs()
          }
        }
        .foregroundStyle(.red)

        Button("Export") {
          exportLogs()
        }
      }
      .padding()

      Divider()

      // Log list
      if isLoading {
        ProgressView("Loading logs...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filteredLogs.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "doc.text")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
          Text("No logs to display")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(filteredLogs) { entry in
          LogEntryRow(entry: entry)
        }
        .listStyle(.inset)
      }

      // Footer
      Divider()
      HStack {
        Text("\(filteredLogs.count) log entries")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if let logURL = getLogFileLocation() {
          Button("Open Log Folder") {
            NSWorkspace.shared.selectFile(
              logURL.path, inFileViewerRootedAtPath: logURL.deletingLastPathComponent().path)
          }
          .buttonStyle(.link)
          .font(.caption)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .frame(minWidth: 700, minHeight: 400)
    .task {
      await loadLogs()
    }
  }

  private var filteredLogs: [LogEntry] {
    var result = logs

    if let level = selectedLevel {
      result = result.filter { $0.level >= level }
    }

    if !searchText.isEmpty {
      result = result.filter {
        $0.message.localizedCaseInsensitiveContains(searchText)
          || $0.fileName.localizedCaseInsensitiveContains(searchText)
          || $0.function.localizedCaseInsensitiveContains(searchText)
      }
    }

    return result.reversed()  // Most recent first
  }

  private func loadLogs() async {
    isLoading = true
    logs = await AppLogger.shared.getLogs()
    isLoading = false
  }

  private func getLogFileLocation() -> URL? {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first
    return appSupport?.appendingPathComponent("MessageBridge/Logs/messagebridge.log")
  }

  private func exportLogs() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = "messagebridge-logs.txt"

    if panel.runModal() == .OK, let url = panel.url {
      let content = filteredLogs.map { $0.formatted }.joined(separator: "\n")
      try? content.write(to: url, atomically: true, encoding: .utf8)
    }
  }
}

struct LogEntryRow: View {
  let entry: LogEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top) {
        Text(entry.level.emoji)
          .font(.system(size: 14))

        VStack(alignment: .leading, spacing: 2) {
          Text(entry.message)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(foregroundColor)
            .textSelection(.enabled)

          HStack(spacing: 12) {
            Text(entry.fileName + ":" + String(entry.line))
              .font(.caption)
              .foregroundStyle(.secondary)

            Text(entry.function)
              .font(.caption)
              .foregroundStyle(.tertiary)

            Spacer()

            Text(formatDate(entry.timestamp))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }

  private var foregroundColor: Color {
    switch entry.level {
    case .debug: return .secondary
    case .info: return .primary
    case .warning: return .orange
    case .error: return .red
    }
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }
}

#Preview {
  LogViewerView()
}
