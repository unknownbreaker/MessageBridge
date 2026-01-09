import SwiftUI

struct LogViewerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedLevel: LogLevel? = nil
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

                Button("Clear Logs") {
                    appState.clearLogs()
                }
                .foregroundStyle(.red)
            }
            .padding()

            Divider()

            // Log list
            if filteredLogs.isEmpty {
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
                    ServerLogEntryRow(entry: entry)
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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var filteredLogs: [LogEntry] {
        var result = appState.logs

        if let level = selectedLevel {
            result = result.filter { $0.level >= level }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                $0.function.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }
}

struct ServerLogEntryRow: View {
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
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    LogViewerView()
        .environmentObject(AppState())
}
