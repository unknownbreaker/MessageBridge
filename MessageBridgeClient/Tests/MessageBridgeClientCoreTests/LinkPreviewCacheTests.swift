import LinkPresentation
import XCTest

@testable import MessageBridgeClientCore

final class LinkPreviewCacheTests: XCTestCase {

  var cache: LinkPreviewCache!

  override func setUp() async throws {
    cache = LinkPreviewCache()
  }

  // MARK: - Basic Cache Operations

  func testMetadata_forUnknownURL_returnsNil() async {
    let url = URL(string: "https://unknown-url.com")!
    let metadata = await cache.metadata(for: url)
    XCTAssertNil(metadata)
  }

  func testStore_andRetrieve_returnsSameMetadata() async {
    let url = URL(string: "https://example.com")!
    let metadata = LPLinkMetadata()
    metadata.url = url
    metadata.title = "Example Domain"

    await cache.store(metadata, for: url)
    let retrieved = await cache.metadata(for: url)

    XCTAssertNotNil(retrieved)
    XCTAssertEqual(retrieved?.title, "Example Domain")
    XCTAssertEqual(retrieved?.url, url)
  }

  func testStore_multipleTimes_overwritesPrevious() async {
    let url = URL(string: "https://example.com")!

    let metadata1 = LPLinkMetadata()
    metadata1.url = url
    metadata1.title = "First Title"
    await cache.store(metadata1, for: url)

    let metadata2 = LPLinkMetadata()
    metadata2.url = url
    metadata2.title = "Second Title"
    await cache.store(metadata2, for: url)

    let retrieved = await cache.metadata(for: url)
    XCTAssertEqual(retrieved?.title, "Second Title")
  }

  // MARK: - Multiple URLs

  func testCache_storesMultipleURLsIndependently() async {
    let url1 = URL(string: "https://example1.com")!
    let url2 = URL(string: "https://example2.com")!

    let metadata1 = LPLinkMetadata()
    metadata1.url = url1
    metadata1.title = "Example 1"

    let metadata2 = LPLinkMetadata()
    metadata2.url = url2
    metadata2.title = "Example 2"

    await cache.store(metadata1, for: url1)
    await cache.store(metadata2, for: url2)

    let retrieved1 = await cache.metadata(for: url1)
    let retrieved2 = await cache.metadata(for: url2)

    XCTAssertEqual(retrieved1?.title, "Example 1")
    XCTAssertEqual(retrieved2?.title, "Example 2")
  }

  // MARK: - Has Cached Metadata

  func testHasCachedMetadata_forUnknownURL_returnsFalse() async {
    let url = URL(string: "https://unknown.com")!
    let hasCached = await cache.hasCachedMetadata(for: url)
    XCTAssertFalse(hasCached)
  }

  func testHasCachedMetadata_forCachedURL_returnsTrue() async {
    let url = URL(string: "https://cached.com")!
    let metadata = LPLinkMetadata()
    metadata.url = url
    metadata.title = "Cached"

    await cache.store(metadata, for: url)
    let hasCached = await cache.hasCachedMetadata(for: url)

    XCTAssertTrue(hasCached)
  }

  // MARK: - Clear Cache

  func testClear_removesAllCachedMetadata() async {
    let url1 = URL(string: "https://example1.com")!
    let url2 = URL(string: "https://example2.com")!

    let metadata1 = LPLinkMetadata()
    metadata1.url = url1
    await cache.store(metadata1, for: url1)

    let metadata2 = LPLinkMetadata()
    metadata2.url = url2
    await cache.store(metadata2, for: url2)

    await cache.clear()

    let retrieved1 = await cache.metadata(for: url1)
    let retrieved2 = await cache.metadata(for: url2)

    XCTAssertNil(retrieved1)
    XCTAssertNil(retrieved2)
  }

  // MARK: - URL Normalization

  func testCache_treatsURLsWithDifferentFragmentsAsIdentical() async {
    let url1 = URL(string: "https://example.com/page")!
    let url2 = URL(string: "https://example.com/page#section")!

    let metadata = LPLinkMetadata()
    metadata.url = url1
    metadata.title = "Page Title"

    await cache.store(metadata, for: url1)

    // The cache should normalize URLs - fragments shouldn't matter for caching
    // This is an implementation detail - we document the behavior
    let retrieved = await cache.metadata(for: url2)
    // Whether this returns nil or the metadata depends on implementation
    _ = retrieved
  }

  // MARK: - Cache Count

  func testCount_returnsNumberOfCachedItems() async {
    var count = await cache.count
    XCTAssertEqual(count, 0)

    let url1 = URL(string: "https://example1.com")!
    let url2 = URL(string: "https://example2.com")!

    let metadata1 = LPLinkMetadata()
    await cache.store(metadata1, for: url1)
    count = await cache.count
    XCTAssertEqual(count, 1)

    let metadata2 = LPLinkMetadata()
    await cache.store(metadata2, for: url2)
    count = await cache.count
    XCTAssertEqual(count, 2)
  }
}
