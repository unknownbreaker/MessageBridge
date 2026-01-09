import SwiftUI
import MessageBridgeClientCore

struct ContentView: View {
    @EnvironmentObject var viewModel: MessagesViewModel
    @State private var selectedConversation: Conversation?
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            ConversationListView(
                conversations: filteredConversations,
                selection: $selectedConversation,
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
        .onChange(of: selectedConversation) { newValue in
            viewModel.selectConversation(newValue?.id)
        }
        .task {
            await viewModel.requestNotificationPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConversation)) { notification in
            if let conversationId = notification.userInfo?["conversationId"] as? String {
                // Find and select the conversation
                selectedConversation = viewModel.conversations.first { $0.id == conversationId }
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
