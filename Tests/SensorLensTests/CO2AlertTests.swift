import XCTest
@testable import SensorLens

final class CO2AlertTests: XCTestCase {
    private func reading(_ id: String, _ name: String, co2: Double?, stale: Bool = false) -> DeviceReading {
        var metrics: [String: Double] = ["temperature_c": 22]
        if let co2 { metrics["co2_ppm"] = co2 }
        return DeviceReading(deviceID: id, name: name, deviceType: "MeterPro(CO2)",
                             metrics: metrics, ts: 1000, stale: stale)
    }

    private let warn = 1000.0
    private let alert = 1500.0

    /// With more than one CO2 meter, the alert has to be about the worst room —
    /// not the first one found, and not whichever happens to be on the bar.
    func testPicksTheWorstOfSeveralSensors() {
        let got = CO2Level.worst([
            reading("A", "Room 1", co2: 600),
            reading("B", "Room 3", co2: 1800),
            reading("C", "Bedroom", co2: 1100),
        ], warn: warn, alert: alert)

        XCTAssertEqual(got?.deviceID, "B")
        XCTAssertEqual(got?.level, .high)
    }

    /// Naming the room is the point: "CO2 is high" across three meters is not
    /// something anyone can act on.
    func testCarriesTheRoomName() {
        let got = CO2Level.worst([reading("B", "Room 3", co2: 1800)], warn: warn, alert: alert)
        XCTAssertEqual(got?.name, "Room 3")
        XCTAssertEqual(got?.ppm, 1800)
    }

    /// A number from a meter that stopped reporting hours ago says nothing about
    /// the air now, and must not raise — or suppress — an alert.
    func testIgnoresStaleSensors() {
        let got = CO2Level.worst([
            reading("A", "Room 1", co2: 600),
            reading("B", "Shed", co2: 2400, stale: true),
        ], warn: warn, alert: alert)

        XCTAssertEqual(got?.deviceID, "A")
        XCTAssertEqual(got?.level, .ok)
    }

    func testIgnoresDevicesWithoutCO2() {
        let got = CO2Level.worst([
            reading("MET", "Bedroom", co2: nil),
            reading("A", "Room 1", co2: 900),
        ], warn: warn, alert: alert)

        XCTAssertEqual(got?.deviceID, "A")
    }

    func testNoCO2SensorsAtAll() {
        XCTAssertNil(CO2Level.worst([reading("MET", "Bedroom", co2: nil)], warn: warn, alert: alert))
        XCTAssertNil(CO2Level.worst([], warn: warn, alert: alert))
    }

    /// All quiet still reports — the menu bar needs to know the difference
    /// between "fine" and "no CO2 sensor here".
    func testCalmReportsOK() {
        let got = CO2Level.worst([reading("A", "Room 1", co2: 500)], warn: warn, alert: alert)
        XCTAssertEqual(got?.level, .ok)
    }

    func testThresholdsAreRespected() {
        let readings = [reading("A", "Room 1", co2: 1200)]
        XCTAssertEqual(CO2Level.worst(readings, warn: 1000, alert: 1500)?.level, .elevated)
        // Someone who tightened the thresholds must get the stricter answer.
        XCTAssertEqual(CO2Level.worst(readings, warn: 800, alert: 1100)?.level, .high)
    }
}
