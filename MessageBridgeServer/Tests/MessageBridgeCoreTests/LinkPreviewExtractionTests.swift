import LinkPresentation
import XCTest

@testable import MessageBridgeCore

final class LinkPreviewExtractionTests: XCTestCase {

  func testExtractLinkPreview_withValidMetadata_returnsPreview() throws {
    // Create a real LPLinkMetadata and archive it
    let metadata = LPLinkMetadata()
    metadata.url = URL(string: "https://apple.com")!
    metadata.title = "Apple"

    let data = try NSKeyedArchiver.archivedData(
      withRootObject: metadata, requiringSecureCoding: false
    )

    let preview = LinkPreviewExtractor.extract(from: data)
    XCTAssertNotNil(preview)
    XCTAssertEqual(preview?.url, "https://apple.com")
    XCTAssertEqual(preview?.title, "Apple")
  }

  func testExtractLinkPreview_withCorruptData_returnsNil() {
    let corruptData = Data([0x00, 0x01, 0x02, 0x03])
    let preview = LinkPreviewExtractor.extract(from: corruptData)
    XCTAssertNil(preview)
  }

  func testExtractLinkPreview_withEmptyData_returnsNil() {
    let preview = LinkPreviewExtractor.extract(from: Data())
    XCTAssertNil(preview)
  }
}
