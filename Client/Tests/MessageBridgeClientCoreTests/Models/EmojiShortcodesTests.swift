import XCTest

@testable import MessageBridgeClientCore

final class EmojiShortcodesTests: XCTestCase {

  // MARK: - lookup

  func testLookup_knownShortcode_returnsEmoji() {
    XCTAssertEqual(EmojiShortcodes.lookup("thumbsup"), "👍")
    XCTAssertEqual(EmojiShortcodes.lookup("fire"), "🔥")
    XCTAssertEqual(EmojiShortcodes.lookup("heart"), "❤️")
  }

  func testLookup_unknownShortcode_returnsNil() {
    XCTAssertNil(EmojiShortcodes.lookup("notarealemoji"))
    XCTAssertNil(EmojiShortcodes.lookup(""))
  }

  func testLookup_caseInsensitive() {
    XCTAssertEqual(EmojiShortcodes.lookup("Thumbsup"), "👍")
    XCTAssertEqual(EmojiShortcodes.lookup("FIRE"), "🔥")
  }

  // MARK: - search

  func testSearch_prefixMatch_returnsMatches() {
    let results = EmojiShortcodes.search("thu")
    XCTAssertFalse(results.isEmpty)
    XCTAssertTrue(results.contains(where: { $0.shortcode == "thumbsup" }))
  }

  func testSearch_emptyPrefix_returnsEmpty() {
    let results = EmojiShortcodes.search("")
    XCTAssertTrue(results.isEmpty)
  }

  func testSearch_singleCharPrefix_returnsEmpty() {
    // Require at least 2 chars to avoid noisy results
    let results = EmojiShortcodes.search("t")
    XCTAssertTrue(results.isEmpty)
  }

  func testSearch_noMatch_returnsEmpty() {
    let results = EmojiShortcodes.search("zzzzz")
    XCTAssertTrue(results.isEmpty)
  }

  func testSearch_respectsMaxResults() {
    let results = EmojiShortcodes.search("sm", maxResults: 3)
    XCTAssertLessThanOrEqual(results.count, 3)
  }

  func testSearch_defaultMaxResults_is8() {
    // "he" should match many emoji (heart, heavy_check_mark, etc.)
    let results = EmojiShortcodes.search("he")
    XCTAssertLessThanOrEqual(results.count, 8)
  }

  func testSearch_matchContainsShortcodeAndEmoji() {
    let results = EmojiShortcodes.search("fire")
    guard let match = results.first(where: { $0.shortcode == "fire" }) else {
      XCTFail("Expected fire match")
      return
    }
    XCTAssertEqual(match.emoji, "🔥")
    XCTAssertEqual(match.shortcode, "fire")
  }

  func testSearch_caseInsensitive() {
    let lower = EmojiShortcodes.search("thu")
    let upper = EmojiShortcodes.search("THU")
    XCTAssertEqual(lower.map(\.shortcode), upper.map(\.shortcode))
  }

  func testSearch_exactMatchSortedFirst() {
    let results = EmojiShortcodes.search("heart")
    // "heart" exact match should come before "heart_eyes", "heartbeat", etc.
    XCTAssertEqual(results.first?.shortcode, "heart")
  }

  // MARK: - Match type

  func testMatch_isEquatable() {
    let a = EmojiShortcodes.Match(shortcode: "fire", emoji: "🔥")
    let b = EmojiShortcodes.Match(shortcode: "fire", emoji: "🔥")
    XCTAssertEqual(a, b)
  }

  // MARK: - Data coverage

  func testDictionary_hasCommonEmoji() {
    // Spot-check key emoji categories exist
    XCTAssertNotNil(EmojiShortcodes.lookup("smile"))
    XCTAssertNotNil(EmojiShortcodes.lookup("wave"))
    XCTAssertNotNil(EmojiShortcodes.lookup("100"))
    XCTAssertNotNil(EmojiShortcodes.lookup("eyes"))
    XCTAssertNotNil(EmojiShortcodes.lookup("pray"))
    XCTAssertNotNil(EmojiShortcodes.lookup("rocket"))
    XCTAssertNotNil(EmojiShortcodes.lookup("tada"))
    XCTAssertNotNil(EmojiShortcodes.lookup("thinking"))
  }

  // MARK: - Adversarial: Unicode edge cases

  /// Bug: lookup with emoji characters in the shortcode name should not crash or match
  func testLookup_emojiAsShortcode_returnsNil() {
    XCTAssertNil(EmojiShortcodes.lookup("\u{1F525}"))  // fire emoji itself
    XCTAssertNil(EmojiShortcodes.lookup("\u{200D}"))  // zero-width joiner
    XCTAssertNil(EmojiShortcodes.lookup("\u{FE0F}"))  // variation selector
  }

  /// Bug: CJK characters in shortcode should not crash
  func testLookup_CJKCharacters_returnsNil() {
    XCTAssertNil(EmojiShortcodes.lookup("\u{4E2D}\u{6587}"))  // Chinese
    XCTAssertNil(EmojiShortcodes.lookup("\u{D55C}\u{AE00}"))  // Korean
  }

  /// Bug: RTL text in shortcode should not match or crash
  func testLookup_RTLText_returnsNil() {
    XCTAssertNil(EmojiShortcodes.lookup("\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}"))
    XCTAssertNil(EmojiShortcodes.lookup("\u{202E}fire"))  // RTL override + "fire"
  }

  /// Bug: newline/tab in shortcode name
  func testLookup_whitespaceCharacters_returnsNil() {
    XCTAssertNil(EmojiShortcodes.lookup("fire\n"))
    XCTAssertNil(EmojiShortcodes.lookup("\tfire"))
    XCTAssertNil(EmojiShortcodes.lookup("fi\tre"))
    XCTAssertNil(EmojiShortcodes.lookup(" fire "))
  }

  /// Bug: very long string should not cause performance issues or crash
  func testLookup_veryLongString_returnsNil() {
    let longString = String(repeating: "a", count: 100_000)
    XCTAssertNil(EmojiShortcodes.lookup(longString))
  }

  /// Bug: null character in shortcode
  func testLookup_nullCharacter_returnsNil() {
    XCTAssertNil(EmojiShortcodes.lookup("fire\0"))
    XCTAssertNil(EmojiShortcodes.lookup("\0"))
  }

  // MARK: - Adversarial: search edge cases

  /// Bug: search with maxResults 0 should return empty
  func testSearch_maxResultsZero_returnsEmpty() {
    let results = EmojiShortcodes.search("fire", maxResults: 0)
    XCTAssertTrue(results.isEmpty)
  }

  /// Bug: search with negative maxResults -- Swift Array.prefix handles negatives,
  /// but prefix(-1) would crash
  func testSearch_maxResultsOne_returnsSingleResult() {
    let results = EmojiShortcodes.search("fire", maxResults: 1)
    XCTAssertEqual(results.count, 1)
  }

  /// Bug: search with very long prefix should not crash
  func testSearch_veryLongPrefix_returnsEmpty() {
    let longPrefix = String(repeating: "a", count: 100_000)
    let results = EmojiShortcodes.search(longPrefix)
    XCTAssertTrue(results.isEmpty)
  }

  /// Bug: search with unicode prefix should not crash
  func testSearch_unicodePrefix_returnsEmpty() {
    let results = EmojiShortcodes.search("\u{1F525}\u{1F525}")  // two fire emoji
    XCTAssertTrue(results.isEmpty)
  }

  /// Bug: search with exactly 2 chars matches boundary
  func testSearch_exactlyTwoChars_works() {
    let results = EmojiShortcodes.search("fi")
    XCTAssertFalse(results.isEmpty)
    XCTAssertTrue(results.contains(where: { $0.shortcode == "fire" }))
  }

  /// Bug: search treats prefix "+1" correctly (contains special regex char)
  func testSearch_numericShortcodePrefix_works() {
    // "+1" is a shortcode in the dictionary (maps to thumbsup)
    let results = EmojiShortcodes.search("+1")
    // "+1" is exactly 2 chars, should search
    XCTAssertTrue(results.contains(where: { $0.shortcode == "+1" }))
  }

  /// Bug: search with "-1" prefix (minus sign in shortcode)
  func testSearch_negativeShortcodePrefix_works() {
    let results = EmojiShortcodes.search("-1")
    XCTAssertTrue(results.contains(where: { $0.shortcode == "-1" }))
  }

  /// Bug: search prefix with trailing whitespace should not match
  func testSearch_prefixWithTrailingSpace_returnsEmpty() {
    // "fi " has a space -- no shortcodes start with "fi "
    let results = EmojiShortcodes.search("fi ")
    XCTAssertTrue(results.isEmpty)
  }

  /// Bug: exact match should always be first, even if there are alphabetically earlier prefix matches
  func testSearch_exactMatchAlwaysFirst_evenWithEarlierAlpha() {
    // "ok" is an exact shortcode. "ok_hand" starts with "ok" but comes after alphabetically
    let results = EmojiShortcodes.search("ok")
    XCTAssertEqual(results.first?.shortcode, "ok")
  }

  /// Bug: duplicate emoji values in dictionary -- different shortcodes map to same emoji
  /// e.g., "thumbsup" and "+1" both map to thumbsup. Search should return both.
  func testSearch_aliasedShortcodes_bothAppear() {
    let thumbsResults = EmojiShortcodes.search("thumbsup")
    let plusResults = EmojiShortcodes.search("+1")
    // Both should find their respective shortcodes
    XCTAssertTrue(thumbsResults.contains(where: { $0.shortcode == "thumbsup" }))
    XCTAssertTrue(plusResults.contains(where: { $0.shortcode == "+1" }))
  }

  /// Bug: case sensitivity in Match equality -- ensure it differentiates
  func testMatch_differentCase_notEqual() {
    let a = EmojiShortcodes.Match(shortcode: "Fire", emoji: "\u{1F525}")
    let b = EmojiShortcodes.Match(shortcode: "fire", emoji: "\u{1F525}")
    XCTAssertNotEqual(a, b)
  }

  /// Bug: search with mixed case prefix should still return lowercased shortcodes
  func testSearch_mixedCase_returnsLowercasedShortcodes() {
    let results = EmojiShortcodes.search("ThUmB")
    for match in results {
      XCTAssertEqual(
        match.shortcode, match.shortcode.lowercased(),
        "Search results should have lowercased shortcodes")
    }
  }
}
