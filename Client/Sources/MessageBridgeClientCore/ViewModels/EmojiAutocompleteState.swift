import Foundation

/// Manages emoji shortcode autocomplete state for the message composer.
/// Bridges ShortcodeDetector results to SwiftUI-observable published properties.
@MainActor
public class EmojiAutocompleteState: ObservableObject {
  @Published public var isVisible = false
  @Published public var matches: [EmojiShortcodes.Match] = []
  @Published public var selectedIndex = 0

  /// The currently active (partial) shortcode being typed, if any.
  public var activeShortcode: ShortcodeDetector.ActiveShortcode?

  public init() {}

  /// Called on every text change in the composer. Checks for complete shortcode
  /// auto-replacement first, then active shortcode popover display.
  public func handleTextChange(oldValue: String, newValue: String, text: inout String) {
    // Priority 1: Check for complete shortcode (e.g., ":fire:" just closed)
    if let complete = ShortcodeDetector.detectComplete(oldText: oldValue, newText: newValue) {
      text.replaceSubrange(complete.range, with: complete.emoji + " ")
      dismiss()
      return
    }

    // Priority 2: Check for active partial shortcode (e.g., ":thu")
    if let active = ShortcodeDetector.detectActive(oldText: oldValue, newText: newValue) {
      let results = EmojiShortcodes.search(active.query)
      if results.isEmpty {
        dismiss()
      } else {
        activeShortcode = active
        matches = results
        selectedIndex = 0
        isVisible = true
      }
    } else {
      dismiss()
    }
  }

  /// Move selection down in the match list, wrapping around.
  public func moveSelectionDown() {
    guard !matches.isEmpty else { return }
    selectedIndex = (selectedIndex + 1) % matches.count
  }

  /// Move selection up in the match list, wrapping around.
  public func moveSelectionUp() {
    guard !matches.isEmpty else { return }
    selectedIndex = (selectedIndex - 1 + matches.count) % matches.count
  }

  /// Replace the active shortcode in the text with the currently selected emoji.
  public func selectCurrent(in text: inout String) {
    guard isVisible,
      let shortcode = activeShortcode,
      selectedIndex < matches.count
    else { return }

    let emoji = matches[selectedIndex].emoji
    text.replaceSubrange(shortcode.range, with: emoji + " ")
    dismiss()
  }

  /// Select a specific match by index and replace in text.
  public func select(index: Int, in text: inout String) {
    guard isVisible,
      let shortcode = activeShortcode,
      index >= 0, index < matches.count
    else { return }

    let emoji = matches[index].emoji
    text.replaceSubrange(shortcode.range, with: emoji + " ")
    dismiss()
  }

  /// Hide the popover and clear state.
  public func dismiss() {
    isVisible = false
    matches = []
    selectedIndex = 0
    activeShortcode = nil
  }
}
