import XCTest
@testable import SensorLens

final class MenuBarSettingsTests: XCTestCase {
    private func reading(_ id: String, _ name: String, _ metrics: [String: Double]) -> DeviceReading {
        DeviceReading(deviceID: id, name: name, deviceType: "test", metrics: metrics, ts: 1000, stale: false)
    }

    /// Regression: the settings list identified its rows by metric name, so the
    /// "temperature_c" row under every sensor shared one identity and checking
    /// one appeared to check them all. Row identity must carry the device.
    func testRowIdentitiesAreUniqueAcrossDevices() {
        let readings = [
            reading("AAA", "Room 1", ["temperature_c": 27, "humidity_pct": 47, "co2_ppm": 800]),
            reading("BBB", "Bedroom", ["temperature_c": 21, "humidity_pct": 50]),
            reading("CCC", "Outdoor", ["temperature_c": 30, "humidity_pct": 61]),
        ]

        let ids = readings.flatMap { MenuBarSettings.rows(for: $0) }.map(\.id)

        XCTAssertEqual(ids.count, 7) // 3 metrics + 2 + 2
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate row identity: \(ids)")
    }

    func testRowsAreInReadingOrder() {
        let rows = MenuBarSettings.rows(for: reading("AAA", "Room 1", [
            "battery_pct": 100, "co2_ppm": 800, "humidity_pct": 47, "temperature_c": 27,
        ]))

        XCTAssertEqual(rows.map(\.metric), ["temperature_c", "humidity_pct", "co2_ppm", "battery_pct"])
    }

    func testRowsBelongToTheirOwnDevice() {
        let rows = MenuBarSettings.rows(for: reading("BBB", "Bedroom", ["temperature_c": 21]))

        XCTAssertEqual(rows, [MenuBarItem(deviceID: "BBB", metric: "temperature_c")])
    }

    /// The behaviour the broken identity made look wrong: selecting one device's
    /// temperature must leave every other device alone.
    func testSelectingOneDeviceLeavesOthersUnselected() {
        let suite = UserDefaults(suiteName: "sensor-lens-tests-\(UUID().uuidString)")!
        let prefs = Preferences(defaults: suite)

        prefs.add(MenuBarItem(deviceID: "AAA", metric: "temperature_c"))

        XCTAssertTrue(prefs.isOnMenuBar(MenuBarItem(deviceID: "AAA", metric: "temperature_c")))
        XCTAssertFalse(prefs.isOnMenuBar(MenuBarItem(deviceID: "BBB", metric: "temperature_c")))
        XCTAssertFalse(prefs.isOnMenuBar(MenuBarItem(deviceID: "CCC", metric: "temperature_c")))
        XCTAssertEqual(prefs.menuBarItems.count, 1)
    }
}
