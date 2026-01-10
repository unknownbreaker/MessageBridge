import SwiftUI
import MessageBridgeClientCore

struct ContentView: View {
    @EnvironmentObject var viewModel: MessagesViewModel
    @State private var selectedConversationId: String?
    @State private var searchText = ""

    private var selectedConversation: Conversation? {
        guard let id = selectedConversationId else { return nil }
        return viewModel.conversations.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            ConversationListView(
                conversations: filteredConversations,
                selection: $selectedConversationId,
                searchText: $searchText
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 350)
            .searchable(text: $searchText, prompt: "Search conversations")
        } detail: {
            if let conversation = selectedConversation {
                MessageThreadView(conversation: conversation)
            } else {
                Text("Select a conversation")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("MessageBridge")
        .navigationSubtitle(viewModel.connectionStatus.text)
        .onChange(of: selectedConversationId) { newValue in
            viewModel.selectConversation(newValue)
        }
        .task {
            await viewModel.requestNotificationPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConversation)) { notification in
            if let conversationId = notification.userInfo?["conversationId"] as? String {
                selectedConversationId = conversationId
            }
        }
    }

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return viewModel.conversations }
        return viewModel.conversations.filter { conversation in
            conversation.displayName.localizedCaseInsensitiveContains(searchText) ||
            conversation.participants.contains { $0.address.localizedCaseInsensitiveContains(searchText) }
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

extension ConnectionStatus {
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
