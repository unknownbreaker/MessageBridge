import MessageBridgeClientCore
import SwiftUI

/// Displays emoji shortcode autocomplete suggestions above the composer.
struct EmojiAutocompletePopover: View {
  @ObservedObject var state: EmojiAutocompleteState
  @Binding var text: String

  var body: some View {
    if state.isVisible && !state.matches.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(state.matches.enumerated()), id: \.offset) { index, match in
          Button {
            state.select(index: index, in: &text)
          } label: {
            HStack(spacing: 8) {
              Text(match.emoji)
                .font(.title3)
                .frame(width: 24)
              Text(":\(match.shortcode):")
                .font(.body)
                .foregroundStyle(index == state.selectedIndex ? .white : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
              index == state.selectedIndex
                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                : RoundedRectangle(cornerRadius: 6).fill(.clear)
            )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(6)
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(.separator, lineWidth: 0.5)
      )
      .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
      .frame(maxWidth: 260)
    }
  }
}
