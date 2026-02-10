import XCTest

@testable import MessageBridgeClientCore

final class ZoomableImageViewTests: XCTestCase {
  func testClampedScale_belowMinimum_returnsMinimum() {
    let scale = ZoomableImageView.clampedScale(0.3, min: 1.0, max: 5.0)
    XCTAssertEqual(scale, 1.0)
  }

  func testClampedScale_aboveMaximum_returnsMaximum() {
    let scale = ZoomableImageView.clampedScale(10.0, min: 1.0, max: 5.0)
    XCTAssertEqual(scale, 5.0)
  }

  func testClampedScale_withinRange_returnsValue() {
    let scale = ZoomableImageView.clampedScale(2.5, min: 1.0, max: 5.0)
    XCTAssertEqual(scale, 2.5)
  }

  func testResetZoom_returnsDefaults() {
    let (scale, offset) = ZoomableImageView.clampAndReset()
    XCTAssertEqual(scale, 1.0)
    XCTAssertEqual(offset, .zero)
  }
}
