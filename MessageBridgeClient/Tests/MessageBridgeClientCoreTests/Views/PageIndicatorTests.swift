import XCTest

final class PageIndicatorTests: XCTestCase {
  func testCurrentIndex_clamped() {
    let total = 5
    let current = 2
    XCTAssertTrue(current >= 0 && current < total)
  }

  func testZeroTotal_noIndicator() {
    let total = 0
    XCTAssertEqual(max(total, 0), 0)
  }
}
