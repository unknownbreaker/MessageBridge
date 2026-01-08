import SwiftUI

@main
struct MessageBridgeApp: App {
    @StateObject private var viewModel = MessagesViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    // TODO: Implement new message
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
