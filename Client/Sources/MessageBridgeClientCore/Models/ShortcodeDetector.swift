import Foundation

/// Detects emoji shortcode patterns in text as the user types.
/// Uses text diffing (old vs new) to infer edit position since SwiftUI's
/// TextEditor doesn't expose cursor position.
public enum ShortcodeDetector {

  /// An in-progress shortcode the user is actively typing.
  public struct ActiveShortcode: Equatable, Sendable {
    /// The query text after the colon (e.g., "thu" from ":thu")
    public let query: String
    /// The range in the text covering the full `:query` (for replacement)
    public let range: Range<String.Index>
  }

  /// A completed shortcode that was just closed with a trailing colon.
  public struct CompleteShortcode: Equatable, Sendable {
    /// The resolved emoji character
    public let emoji: String
    /// The range in the text covering `:shortcode:` (for replacement)
    public let range: Range<String.Index>
  }

  /// Detect a partial shortcode being typed (e.g., ":thu").
  /// Returns nil if no active shortcode pattern is found at the edit point.
  public static func detectActive(oldText: String, newText: String) -> ActiveShortcode? {
    let editIndex = findEditIndex(oldText: oldText, newText: newText)
    guard let editIdx = editIndex else { return nil }

    // Scan backward from edit point for ':'
    guard let colonIdx = scanBackwardForColon(in: newText, from: editIdx) else {
      return nil
    }

    // Check: the newly typed char might be a closing colon → not active
    if editIdx < newText.endIndex && newText[editIdx] == ":" && editIdx != colonIdx {
      return nil
    }

    // Extract the query (text between colon and end-of-edit area)
    let queryStart = newText.index(after: colonIdx)
    // The end of the query is the end of the edited region
    let queryEnd = findQueryEnd(in: newText, from: queryStart)

    guard queryEnd > queryStart else { return nil }

    let query = String(newText[queryStart..<queryEnd])

    // Validate: no spaces allowed
    guard !query.contains(" ") else { return nil }

    // Validate: minimum 2 chars
    guard query.count >= 2 else { return nil }

    // Validate: not a URL (check for :// before the colon)
    if isURLColon(in: newText, colonIndex: colonIdx) { return nil }

    // Check that query doesn't contain another colon (would mean it's closed)
    guard !query.contains(":") else { return nil }

    let range = colonIdx..<queryEnd
    return ActiveShortcode(query: query, range: range)
  }

  /// Detect a just-completed shortcode (e.g., user just typed the closing ":" in ":fire:").
  /// Returns nil if no valid complete shortcode was just closed.
  public static func detectComplete(oldText: String, newText: String) -> CompleteShortcode? {
    // The new text should be longer and the last typed char should be ':'
    guard newText.count > oldText.count else { return nil }

    let editIndex = findEditIndex(oldText: oldText, newText: newText)
    guard let editIdx = editIndex else { return nil }

    // The character at editIdx should be ':'
    guard editIdx < newText.endIndex && newText[editIdx] == ":" else { return nil }

    // Scan backward from just before the closing colon for the opening ':'
    guard editIdx > newText.startIndex else { return nil }
    let beforeClosing = newText.index(before: editIdx)

    guard let openColon = scanBackwardForColon(in: newText, from: beforeClosing) else {
      return nil
    }

    // Make sure opening colon is different from closing colon
    guard openColon != editIdx else { return nil }

    // Extract shortcode name between the colons
    let nameStart = newText.index(after: openColon)
    let name = String(newText[nameStart..<editIdx])

    // Validate: not empty, no spaces
    guard !name.isEmpty, !name.contains(" ") else { return nil }

    // Look up in emoji dictionary
    guard let emoji = EmojiShortcodes.lookup(name) else { return nil }

    let closingEnd = newText.index(after: editIdx)
    let range = openColon..<closingEnd
    return CompleteShortcode(emoji: emoji, range: range)
  }

  // MARK: - Private helpers

  /// Find the index in newText where the edit occurred by diffing from the start.
  private static func findEditIndex(oldText: String, newText: String) -> String.Index? {
    var oldIdx = oldText.startIndex
    var newIdx = newText.startIndex

    // Find first differing position
    while oldIdx < oldText.endIndex && newIdx < newText.endIndex {
      if oldText[oldIdx] != newText[newIdx] { break }
      oldIdx = oldText.index(after: oldIdx)
      newIdx = newText.index(after: newIdx)
    }

    // If we reached the end of old text, the edit is at newIdx (insertion)
    // If we reached the end of new text, the edit is at newIdx (deletion)
    // If neither, the edit is at newIdx (replacement)
    guard newIdx <= newText.endIndex else { return nil }
    return newIdx
  }

  /// Scan backward from the given index to find a ':' character.
  /// If `index` is at `endIndex`, starts scanning from the last character.
  private static func scanBackwardForColon(
    in text: String, from index: String.Index
  ) -> String.Index? {
    guard !text.isEmpty else { return nil }
    var idx = index
    // If at endIndex, step back to last valid character
    if idx == text.endIndex {
      idx = text.index(before: idx)
    }
    while idx >= text.startIndex {
      if text[idx] == ":" { return idx }
      // Stop at spaces — shortcode can't span spaces
      if text[idx] == " " { return nil }
      if idx == text.startIndex { break }
      idx = text.index(before: idx)
    }
    return nil
  }

  /// Find the end of the query — from the query start to the next space, colon, or end of string.
  private static func findQueryEnd(in text: String, from start: String.Index) -> String.Index {
    var idx = start
    while idx < text.endIndex {
      let ch = text[idx]
      if ch == " " || ch == ":" { return idx }
      idx = text.index(after: idx)
    }
    return text.endIndex
  }

  /// Check if the colon at the given index is part of a URL scheme (e.g., "https://").
  private static func isURLColon(in text: String, colonIndex: String.Index) -> Bool {
    // Check for "://" after the colon
    let afterColon = text.index(after: colonIndex)
    guard afterColon < text.endIndex else { return false }

    let twoAfter = text.index(after: afterColon)
    guard twoAfter <= text.endIndex else { return false }

    if afterColon < text.endIndex && text[afterColon] == "/" {
      if twoAfter < text.endIndex && text[twoAfter] == "/" {
        return true
      }
    }

    // Also check if there's a protocol-like word before the colon (http, https, ftp)
    // by scanning backward for common URL prefixes
    if colonIndex > text.startIndex {
      var wordStart = colonIndex
      while wordStart > text.startIndex {
        let prev = text.index(before: wordStart)
        if text[prev].isLetter {
          wordStart = prev
        } else {
          break
        }
      }

      let word = String(text[wordStart..<colonIndex]).lowercased()
      if word == "http" || word == "https" || word == "ftp" || word == "ftps" {
        return true
      }

      // Check for port numbers — digits after colon in a URL context
      // If the text before colon ends with a domain-like pattern (letters/dots/digits)
      // and after colon is digits, it's likely a port (e.g., localhost:8080, 192.168.1.1:8080)
      if afterColon < text.endIndex && text[afterColon].isNumber {
        if colonIndex > text.startIndex {
          let beforeColon = text.index(before: colonIndex)
          if text[beforeColon].isLetter || text[beforeColon] == "."
            || text[beforeColon].isNumber
          {
            return true
          }
        }
      }
    }

    return false
  }
}
