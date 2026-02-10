import MessageBridgeClientCore
import SwiftUI

/// Renders toolbar buttons for all registered composer plugins.
///
/// When no plugins are registered, renders nothing.
struct ComposerToolbar: View {
  let context: any ComposerContext

  var body: some View {
    let plugins = ComposerRegistry.shared.all.filter {
      $0.showsToolbarButton(context: context)
    }

    if !plugins.isEmpty {
      HStack(spacing: 4) {
        ForEach(plugins, id: \.id) { plugin in
          Button {
            Task { await plugin.activate(context: context) }
          } label: {
            Image(systemName: plugin.icon)
          }
          .buttonStyle(.borderless)
        }
      }
    }
  }
}
