import XCTest
@testable import SensorLens

final class FormattingTests: XCTestCase {
    /// These are the exact strings the CLI's `cmd/format.go` produces, asserted
    /// here so the two renderings cannot drift apart. If this fails, one side
    /// was changed without the other.
    func testValueMatchesTheCLI() {
        XCTAssertEqual(Format.value("temperature_c", 27.24), "27.2°C")
        XCTAssertEqual(Format.value("humidity_pct", 47), "47%")
        XCTAssertEqual(Format.value("co2_ppm", 1148), "1148 ppm")
        XCTAssertEqual(Format.value("battery_pct", 100), "bat 100%")
        XCTAssertEqual(Format.value("light_level", 1), "light 1")
        XCTAssertEqual(Format.value("vpd_kpa", 1.914), "vpd 1.91 kPa")
        // Unknown metrics are passed through by the extractor, so they must
        // still render readably.
        XCTAssertEqual(Format.value("brightness", 42), "brightness=42")
    }

    /// `bare` drops the disambiguating prefix, for places where the metric is
    /// already labelled.
    func testBareDropsThePrefix() {
        XCTAssertEqual(Format.bare("battery_pct", 100), "100%")
        XCTAssertEqual(Format.bare("light_level", 1), "1")
        XCTAssertEqual(Format.bare("temperature_c", 27.24), "27.2°C")
    }

    func testSortMetrics() {
        let got = Format.sortMetrics(["battery_pct", "vpd_kpa", "co2_ppm", "temperature_c", "humidity_pct"])
        XCTAssertEqual(got, ["temperature_c", "humidity_pct", "co2_ppm", "battery_pct", "vpd_kpa"])
    }

    func testSortMetricsPutsUnknownsLastAlphabetically() {
        let got = Format.sortMetrics(["zebra", "temperature_c", "alpha"])
        XCTAssertEqual(got, ["temperature_c", "alpha", "zebra"])
    }

    func testAge() {
        XCTAssertEqual(Format.age(45), "45s ago")
        XCTAssertEqual(Format.age(300), "5m ago")
        XCTAssertEqual(Format.age(3660), "1h 1m ago")
        XCTAssertEqual(Format.age(90000), "1d 1h ago")
    }

    func testCO2Bands() {
        XCTAssertEqual(CO2Level.of(600, warn: 1000, alert: 1500), .ok)
        XCTAssertEqual(CO2Level.of(1200, warn: 1000, alert: 1500), .elevated)
        XCTAssertEqual(CO2Level.of(1600, warn: 1000, alert: 1500), .high)
        // Boundaries belong to the higher band: 1000 ppm is already elevated.
        XCTAssertEqual(CO2Level.of(1000, warn: 1000, alert: 1500), .elevated)
        XCTAssertEqual(CO2Level.of(1500, warn: 1000, alert: 1500), .high)
    }
}
