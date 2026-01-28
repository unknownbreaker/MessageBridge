import XCTest

@testable import MessageBridgeClient
@testable import MessageBridgeClientCore

final class CarouselViewTests: XCTestCase {
  func testClampedIndex_outOfBounds_clamped() {
    let clamped = CarouselView.clampedIndex(5, count: 3)
    XCTAssertEqual(clamped, 2)
  }

  func testClampedIndex_negative_clamped() {
    let clamped = CarouselView.clampedIndex(-1, count: 3)
    XCTAssertEqual(clamped, 0)
  }

  func testClampedIndex_valid_unchanged() {
    let clamped = CarouselView.clampedIndex(1, count: 3)
    XCTAssertEqual(clamped, 1)
  }

  func testClampedIndex_emptyCount_returnsZero() {
    let clamped = CarouselView.clampedIndex(0, count: 0)
    XCTAssertEqual(clamped, 0)
  }
}
