import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: MessagesViewModel
    @State private var selectedConversation: Conversation?
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            ConversationListView(
                conversations: viewModel.conversations,
                selection: $selectedConversation,
                searchText: $searchText
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 350)
        } detail: {
            if let conversation = selectedConversation {
                MessageThreadView(conversation: conversation)
            } else {
                Text("Select a conversation")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ConnectionStatusView(status: viewModel.connectionStatus)
            }
        }
    }
}

struct ConnectionStatusView: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum ConnectionStatus {
    case connected
    case connecting
    case disconnected

    var color: Color {
        switch self {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        }
    }

    var text: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MessagesViewModel())
}
