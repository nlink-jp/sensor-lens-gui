import XCTest
@testable import SensorLens

final class SparklineTests: XCTestCase {
    /// A room that moved between 26 and 28 degrees must look like it moved. A
    /// domain anchored at zero would draw it as a flat line near the top.
    func testDomainFollowsTheDataNotZero() {
        let range = Sparkline.domain([26, 27, 28])

        XCTAssertGreaterThan(range.lowerBound, 20, "domain reaches far below the data")
        XCTAssertLessThan(range.lowerBound, 26)
        XCTAssertGreaterThan(range.upperBound, 28)
    }

    /// A genuinely flat series should sit through the middle, not along an edge.
    func testFlatSeriesIsNotPinnedToAnEdge() {
        let range = Sparkline.domain([22, 22, 22])

        XCTAssertLessThan(range.lowerBound, 22)
        XCTAssertGreaterThan(range.upperBound, 22)
    }

    func testDomainOfNothing() {
        XCTAssertEqual(Sparkline.domain([]), 0...1)
    }

    func testRisingAndFalling() {
        XCTAssertEqual(Sparkline.trend([20, 22, 25, 28]), .rising)
        XCTAssertEqual(Sparkline.trend([28, 25, 22, 20]), .falling)
    }

    func testSteadyDespiteWobble() {
        // Sensor noise around a constant value is not a trend.
        XCTAssertEqual(Sparkline.trend([22.0, 22.1, 21.9, 22.05]), .steady)
    }

    /// The threshold scales with the range, so a move registers whether the
    /// metric swings by hundreds (CO2 ppm) or by ones (degrees) — no per-metric
    /// table of "what counts as a change" to keep up to date.
    func testThresholdScalesWithTheMetric() {
        XCTAssertEqual(Sparkline.trend([500, 700, 900, 1200]), .rising)
        XCTAssertEqual(Sparkline.trend([21.0, 21.5, 22.0, 22.5]), .rising)
    }

    /// The arrow describes the **drawn** shape, not an absolute magnitude.
    ///
    /// The sparkline is autoscaled to its own data, so even a 1.5 ppm climb is
    /// drawn as a clearly rising line. An arrow reading "steady" beside a
    /// visibly climbing line would contradict the picture next to it, so a
    /// monotonic climb is rising however small it is in absolute terms.
    func testTheArrowAgreesWithTheDrawnLine() {
        XCTAssertEqual(Sparkline.trend([800, 800.5, 801, 801.5]), .rising)
    }

    /// Two samples cannot support a claim about a six-hour direction, so the
    /// answer is "no answer" rather than a confidently wrong "steady".
    func testTooFewSamplesGivesNoTrend() {
        XCTAssertNil(Sparkline.trend([]))
        XCTAssertNil(Sparkline.trend([22]))
        XCTAssertNil(Sparkline.trend([22, 25]))
    }
}
