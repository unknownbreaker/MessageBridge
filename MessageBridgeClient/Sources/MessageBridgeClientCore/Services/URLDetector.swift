import Foundation

/// Utility to detect and extract URLs from text using NSDataDetector
public struct URLDetector {

    /// Extract all URLs from the given text
    /// - Parameter text: The text to search for URLs
    /// - Returns: An array of URLs found in the text, in order of appearance
    public static func detectURLs(in text: String) -> [URL] {
        guard !text.isEmpty else { return [] }

        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let range = NSRange(text.startIndex..., in: text)

            let matches = detector.matches(in: text, options: [], range: range)

            return matches.compactMap { match -> URL? in
                guard let url = match.url else { return nil }
                return url
            }
        } catch {
            // NSDataDetector creation failed - shouldn't happen in practice
            return []
        }
    }

    /// Get the first URL found in the text, if any
    /// - Parameter text: The text to search for URLs
    /// - Returns: The first URL found, or nil if no URLs are present
    public static func firstURL(in text: String) -> URL? {
        return detectURLs(in: text).first
    }

    /// Check if the text contains any URLs
    /// - Parameter text: The text to check
    /// - Returns: True if at least one URL is found
    public static func containsURL(in text: String) -> Bool {
        return firstURL(in: text) != nil
    }
}
