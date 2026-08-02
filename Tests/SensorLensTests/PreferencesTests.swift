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

    /// Selection is per device × metric, so one sensor can contribute only its
    /// CO2 while another contributes only its temperature.
    func testSelectionIsPerDeviceAndMetric() {
        let prefs = makePrefs()
        prefs.add(MenuBarItem(deviceID: "AAA", metric: "co2_ppm"))

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
        [a, b, c].forEach(prefs.add)

        prefs.moveMenuBarItems(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(prefs.menuBarItems, [c, a, b])
    }

    func testMoveOnePlace() {
        let prefs = makePrefs()
        let a = MenuBarItem(deviceID: "A", metric: "temperature_c")
        let b = MenuBarItem(deviceID: "B", metric: "co2_ppm")
        let c = MenuBarItem(deviceID: "C", metric: "humidity_pct")
        [a, b, c].forEach(prefs.add)

        prefs.moveMenuBarItem(b, by: -1)
        XCTAssertEqual(prefs.menuBarItems, [b, a, c])

        prefs.moveMenuBarItem(b, by: 1)
        XCTAssertEqual(prefs.menuBarItems, [a, b, c])
    }

    /// The ends must hold: a move off either edge is a no-op, not a crash or a
    /// wrap-around to the other side.
    func testMoveOffTheEndsDoesNothing() {
        let prefs = makePrefs()
        let a = MenuBarItem(deviceID: "A", metric: "temperature_c")
        let b = MenuBarItem(deviceID: "B", metric: "co2_ppm")
        [a, b].forEach(prefs.add)

        prefs.moveMenuBarItem(a, by: -1)
        prefs.moveMenuBarItem(b, by: 1)
        XCTAssertEqual(prefs.menuBarItems, [a, b])

        // An item that is not on the bar at all must also be harmless.
        prefs.moveMenuBarItem(MenuBarItem(deviceID: "Z", metric: "x"), by: -1)
        XCTAssertEqual(prefs.menuBarItems, [a, b])
    }

    func testAddRespectsTheCapAndRefusesDuplicates() {
        let prefs = makePrefs()
        let a = MenuBarItem(deviceID: "A", metric: "temperature_c")

        prefs.add(a)
        prefs.add(a) // already there
        XCTAssertEqual(prefs.menuBarItems, [a])

        for i in 0..<Preferences.maxMenuBarItems {
            prefs.add(MenuBarItem(deviceID: "D\(i)", metric: "temperature_c"))
        }
        XCTAssertEqual(prefs.menuBarItems.count, Preferences.maxMenuBarItems)
        XCTAssertEqual(prefs.menuBarItems.first, a, "the cap must not evict an earlier choice")
    }

    func testRemove() {
        let prefs = makePrefs()
        let a = MenuBarItem(deviceID: "A", metric: "temperature_c")
        let b = MenuBarItem(deviceID: "B", metric: "co2_ppm")
        [a, b].forEach(prefs.add)

        prefs.remove(a)
        XCTAssertEqual(prefs.menuBarItems, [b])

        prefs.remove(a) // already gone
        XCTAssertEqual(prefs.menuBarItems, [b])
    }

    func testReorderPersists() {
        let suite = UserDefaults(suiteName: "sensor-lens-tests-\(UUID().uuidString)")!
        let first = Preferences(defaults: suite)
        let a = MenuBarItem(deviceID: "A", metric: "temperature_c")
        let b = MenuBarItem(deviceID: "B", metric: "co2_ppm")
        [a, b].forEach(first.add)

        first.moveMenuBarItems(from: IndexSet(integer: 1), to: 0)

        XCTAssertEqual(Preferences(defaults: suite).menuBarItems, [b, a])
    }

    func testPersistsAcrossInstances() {
        let suite = UserDefaults(suiteName: "sensor-lens-tests-\(UUID().uuidString)")!
        let first = Preferences(defaults: suite)
        first.add(MenuBarItem(deviceID: "AAA", metric: "co2_ppm"))
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
        prefs.add(MenuBarItem(deviceID: "MET", metric: "humidity_pct"))

        prefs.seedIfEmpty(from: [reading("CO2", "Room 1", ["co2_ppm": 800, "temperature_c": 27])])

        XCTAssertEqual(prefs.menuBarItems, [MenuBarItem(deviceID: "MET", metric: "humidity_pct")])
    }

    func testPruneDropsDevicesNoLongerCollected() {
        let prefs = makePrefs()
        prefs.add(MenuBarItem(deviceID: "KEEP", metric: "temperature_c"))
        prefs.add(MenuBarItem(deviceID: "GONE", metric: "temperature_c"))

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
        prefs.add(MenuBarItem(deviceID: "AAA", metric: "temperature_c"))

        prefs.prune(toCollected: [])

        XCTAssertEqual(prefs.menuBarItems.count, 1)
    }
}
