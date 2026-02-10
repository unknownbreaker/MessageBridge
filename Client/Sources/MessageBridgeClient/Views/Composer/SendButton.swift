import SwiftUI

/// Send button for the message composer.
struct SendButton: View {
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.up.circle.fill")
        .font(.title2)
    }
    .buttonStyle(.plain)
    .foregroundColor(enabled ? .blue : .secondary)
    .disabled(!enabled)
  }
}
