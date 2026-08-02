import XCTest
@testable import SensorLens

final class PopoverLayoutTests: XCTestCase {
    /// Regression: with only a `maxHeight`, the ScrollView's ideal height was
    /// zero, the MenuBarExtra window sized itself to that, and the popover
    /// showed a header sitting directly on a footer. Whatever the row counts,
    /// the answer must be a usable height.
    func testNeverCollapses() {
        for sparklines in 0...3 {
            for devices in 0...30 {
                let h = PopoverLayout.contentHeight(sparklines: sparklines, devices: devices)
                XCTAssertGreaterThanOrEqual(h, PopoverLayout.minimum,
                                            "collapsed at \(sparklines)/\(devices)")
            }
        }
    }

    /// A menu-bar app that runs off the bottom of the screen is no better.
    func testNeverExceedsTheCap() {
        let h = PopoverLayout.contentHeight(sparklines: 3, devices: 200)
        XCTAssertEqual(h, PopoverLayout.maximum)
    }

    func testEmptyStillGetsAHeight() {
        XCTAssertEqual(PopoverLayout.contentHeight(sparklines: 0, devices: 0), PopoverLayout.minimum)
    }

    func testGrowsWithContent() {
        let small = PopoverLayout.contentHeight(sparklines: 1, devices: 2)
        let large = PopoverLayout.contentHeight(sparklines: 3, devices: 6)
        XCTAssertGreaterThan(large, small)
    }

    /// A realistic configuration — three picks and fifteen collected sensors —
    /// should fill the pane rather than leave it half empty.
    func testRealisticConfigurationUsesTheFullPane() {
        XCTAssertEqual(PopoverLayout.contentHeight(sparklines: 3, devices: 15), PopoverLayout.maximum)
    }

    /// A couple of devices and no picks should not reserve a screenful.
    func testSmallConfigurationDoesNotReserveAScreenful() {
        let h = PopoverLayout.contentHeight(sparklines: 0, devices: 2)
        XCTAssertLessThan(h, PopoverLayout.maximum)
    }
}
