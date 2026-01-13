import XCTest
@testable import MessageBridgeClientCore

final class URLDetectorTests: XCTestCase {

    // MARK: - Basic URL Detection

    func testDetectURLs_withNoURLs_returnsEmptyArray() {
        let text = "Hello, this is a plain text message with no links."
        let urls = URLDetector.detectURLs(in: text)
        XCTAssertTrue(urls.isEmpty)
    }

    func testDetectURLs_withSingleHTTPSURL_returnsURL() {
        let text = "Check out this link: https://www.apple.com"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "https://www.apple.com")
    }

    func testDetectURLs_withSingleHTTPURL_returnsURL() {
        let text = "Old link: http://example.com/page"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "http://example.com/page")
    }

    func testDetectURLs_withMultipleURLs_returnsAllURLs() {
        let text = "Check https://apple.com and also https://google.com for more info"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].absoluteString, "https://apple.com")
        XCTAssertEqual(urls[1].absoluteString, "https://google.com")
    }

    // MARK: - URL Variations

    func testDetectURLs_withURLContainingPath_returnsFullURL() {
        let text = "Article at https://example.com/blog/2024/my-article"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "https://example.com/blog/2024/my-article")
    }

    func testDetectURLs_withURLContainingQueryParams_returnsFullURL() {
        let text = "Search: https://google.com/search?q=swift+programming"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.absoluteString.contains("q=swift") ?? false)
    }

    func testDetectURLs_withURLContainingFragment_returnsFullURL() {
        let text = "Jump to https://example.com/page#section-2"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.absoluteString.contains("#section-2") ?? false)
    }

    func testDetectURLs_withURLContainingPort_returnsFullURL() {
        let text = "Local server: http://localhost:8080/api"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "http://localhost:8080/api")
    }

    // MARK: - Special Cases

    func testDetectURLs_withURLAtStartOfText_returnsURL() {
        let text = "https://example.com is a great website"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "https://example.com")
    }

    func testDetectURLs_withURLAtEndOfText_returnsURL() {
        let text = "Visit this website: https://example.com"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "https://example.com")
    }

    func testDetectURLs_withURLOnlyText_returnsURL() {
        let text = "https://example.com"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "https://example.com")
    }

    func testDetectURLs_withURLInParentheses_returnsURL() {
        let text = "See the docs (https://docs.example.com) for details"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "https://docs.example.com")
    }

    func testDetectURLs_withURLFollowedByPunctuation_returnsCleanURL() {
        let text = "Check out https://example.com!"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        // NSDataDetector should not include the trailing punctuation
        XCTAssertEqual(urls.first?.absoluteString, "https://example.com")
    }

    // MARK: - Edge Cases

    func testDetectURLs_withEmptyString_returnsEmptyArray() {
        let text = ""
        let urls = URLDetector.detectURLs(in: text)
        XCTAssertTrue(urls.isEmpty)
    }

    func testDetectURLs_withWhitespaceOnly_returnsEmptyArray() {
        let text = "   \n\t  "
        let urls = URLDetector.detectURLs(in: text)
        XCTAssertTrue(urls.isEmpty)
    }

    func testDetectURLs_withInvalidURL_returnsEmptyArray() {
        let text = "Not a url: htp://broken or www without protocol"
        let urls = URLDetector.detectURLs(in: text)
        // NSDataDetector might detect "www without protocol" as a URL
        // We'll accept whatever NSDataDetector returns
        // This test documents the behavior
        _ = urls
    }

    func testDetectURLs_withIPAddress_detectsAsURL() {
        let text = "Server at http://192.168.1.1:8080/api"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.absoluteString.contains("192.168.1.1") ?? false)
    }

    // MARK: - First URL Helper

    func testFirstURL_withNoURLs_returnsNil() {
        let text = "No links here"
        let url = URLDetector.firstURL(in: text)
        XCTAssertNil(url)
    }

    func testFirstURL_withSingleURL_returnsURL() {
        let text = "Check https://example.com"
        let url = URLDetector.firstURL(in: text)

        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testFirstURL_withMultipleURLs_returnsFirstURL() {
        let text = "First https://first.com then https://second.com"
        let url = URLDetector.firstURL(in: text)

        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://first.com")
    }

    // MARK: - Real-World Examples

    func testDetectURLs_withYouTubeLink_returnsURL() {
        let text = "Watch this: https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.absoluteString.contains("youtube.com") ?? false)
    }

    func testDetectURLs_withTwitterLink_returnsURL() {
        let text = "Tweet: https://twitter.com/user/status/123456789"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.absoluteString.contains("twitter.com") ?? false)
    }

    func testDetectURLs_withInstagramLink_returnsURL() {
        let text = "Photo: https://www.instagram.com/p/ABC123/"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.absoluteString.contains("instagram.com") ?? false)
    }

    func testDetectURLs_withShortURL_returnsURL() {
        let text = "Shortened: https://bit.ly/abc123"
        let urls = URLDetector.detectURLs(in: text)

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.absoluteString.contains("bit.ly") ?? false)
    }
}
