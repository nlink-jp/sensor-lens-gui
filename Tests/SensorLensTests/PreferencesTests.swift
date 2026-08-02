import XCTest
@testable import SensorLens

final class PreferencesTests: XCTestCase {
    private func makePrefs() -> Preferences {
        let suite = UserDefaults(suiteName: "sensor-lens-tests-\(UUID().uuidString)")!
        return Preferences(defaults: suite)
    }

    private func reading(_ id: String, _ name: String, _ metrics: [String: Double]) -> DeviceReading {
        DeviceReading(deviceID: id, name: name, deviceType: "test", metrics: metrics, ts: 1000, stale: false)
    }

    func testToggleAddsAndRemoves() {
        let prefs = makePrefs()
        let item = MenuBarItem(deviceID: "AAA", metric: "co2_ppm")

        prefs.toggleMenuBar(item)
        XCTAssertTrue(prefs.isOnMenuBar(item))

        prefs.toggleMenuBar(item)
        XCTAssertFalse(prefs.isOnMenuBar(item))
    }

    /// The bar has finite room; past the cap a new pick is refused rather than
    /// silently evicting one the user chose earlier.
    func testMenuBarIsCapped() {
        let prefs = makePrefs()
        for i in 0...Preferences.maxMenuBarItems {
            prefs.toggleMenuBar(MenuBarItem(deviceID: "D\(i)", metric: "temperature_c"))
        }
        XCTAssertEqual(prefs.menuBarItems.count, Preferences.maxMenuBarItems)
        XCTAssertTrue(prefs.isMenuBarFull)
    }

    /// Selection is per device × metric, so one sensor can contribute only its
    /// CO2 while another contributes only its temperature.
    func testSelectionIsPerDeviceAndMetric() {
        let prefs = makePrefs()
        prefs.toggleMenuBar(MenuBarItem(deviceID: "AAA", metric: "co2_ppm"))

        XCTAssertTrue(prefs.isOnMenuBar(MenuBarItem(deviceID: "AAA", metric: "co2_ppm")))
        XCTAssertFalse(prefs.isOnMenuBar(MenuBarItem(deviceID: "AAA", metric: "temperature_c")))
    }

    /// Which reading sits leftmost is the one seen without looking, so the order
    /// is a real choice — not an accident of the sequence they were ticked in.
    func testReorder() {
        let prefs = makePrefs()
        let a = MenuBarItem(deviceID: "A", metric: "temperature_c")
        let b = MenuBarItem(deviceID: "B", metric: "co2_ppm")
        let c = MenuBarItem(deviceID: "C", metric: "humidity_pct")
        [a, b, c].forEach(prefs.toggleMenuBar)

        prefs.moveMenuBarItems(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(prefs.menuBarItems, [c, a, b])
    }

    func testReorderPersists() {
        let suite = UserDefaults(suiteName: "sensor-lens-tests-\(UUID().uuidString)")!
        let first = Preferences(defaults: suite)
        let a = MenuBarItem(deviceID: "A", metric: "temperature_c")
        let b = MenuBarItem(deviceID: "B", metric: "co2_ppm")
        [a, b].forEach(first.toggleMenuBar)

        first.moveMenuBarItems(from: IndexSet(integer: 1), to: 0)

        XCTAssertEqual(Preferences(defaults: suite).menuBarItems, [b, a])
    }

    func testPersistsAcrossInstances() {
        let suite = UserDefaults(suiteName: "sensor-lens-tests-\(UUID().uuidString)")!
        let first = Preferences(defaults: suite)
        first.toggleMenuBar(MenuBarItem(deviceID: "AAA", metric: "co2_ppm"))
        first.co2Alert = 1200

        let second = Preferences(defaults: suite)
        XCTAssertTrue(second.isOnMenuBar(MenuBarItem(deviceID: "AAA", metric: "co2_ppm")))
        XCTAssertEqual(second.co2Alert, 1200)
    }

    /// An empty menu bar makes the app look broken on first launch, so a
    /// sensible pick is made for the user — the CO2 sensor if there is one,
    /// since that is the reading with a threshold worth watching.
    func testSeedPrefersTheCO2Sensor() {
        let prefs = makePrefs()
        prefs.seedIfEmpty(from: [
            reading("MET", "Bedroom", ["temperature_c": 21]),
            reading("CO2", "Room 1", ["temperature_c": 27, "co2_ppm": 800]),
        ])

        XCTAssertTrue(prefs.isOnMenuBar(MenuBarItem(deviceID: "CO2", metric: "co2_ppm")))
        XCTAssertFalse(prefs.isOnMenuBar(MenuBarItem(deviceID: "MET", metric: "temperature_c")))
    }

    func testSeedFallsBackToTemperature() {
        let prefs = makePrefs()
        prefs.seedIfEmpty(from: [reading("MET", "Bedroom", ["temperature_c": 21, "humidity_pct": 50])])

        XCTAssertEqual(prefs.menuBarItems, [MenuBarItem(deviceID: "MET", metric: "temperature_c")])
    }

    func testSeedDoesNotOverrideAChoiceAlreadyMade() {
        let prefs = makePrefs()
        prefs.toggleMenuBar(MenuBarItem(deviceID: "MET", metric: "humidity_pct"))

        prefs.seedIfEmpty(from: [reading("CO2", "Room 1", ["co2_ppm": 800, "temperature_c": 27])])

        XCTAssertEqual(prefs.menuBarItems, [MenuBarItem(deviceID: "MET", metric: "humidity_pct")])
    }

    func testPruneDropsDevicesNoLongerCollected() {
        let prefs = makePrefs()
        prefs.toggleMenuBar(MenuBarItem(deviceID: "KEEP", metric: "temperature_c"))
        prefs.toggleMenuBar(MenuBarItem(deviceID: "GONE", metric: "temperature_c"))

        prefs.prune(toCollected: [
            Device(deviceID: "KEEP", name: "Keep", deviceType: "Meter", hubDeviceID: nil,
                   version: nil, enabled: true, firstSeen: 0, lastSeen: 0),
            Device(deviceID: "GONE", name: "Gone", deviceType: "Meter", hubDeviceID: nil,
                   version: nil, enabled: false, firstSeen: 0, lastSeen: 0),
        ])

        XCTAssertEqual(prefs.menuBarItems, [MenuBarItem(deviceID: "KEEP", metric: "temperature_c")])
    }

    /// A failed CLI call returns an empty device list. Treating that as "nothing
    /// is collected" would wipe the user's menu bar over a transient error.
    func testPruneIgnoresAnEmptyDeviceList() {
        let prefs = makePrefs()
        prefs.toggleMenuBar(MenuBarItem(deviceID: "AAA", metric: "temperature_c"))

        prefs.prune(toCollected: [])

        XCTAssertEqual(prefs.menuBarItems.count, 1)
    }
}
