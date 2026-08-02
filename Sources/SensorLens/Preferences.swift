import Foundation

/// Preferences owned by this app.
///
/// The split matters: which devices are *collected* lives in the CLI's
/// config.toml, because the daemon needs it and it costs API calls. Which
/// readings appear *on the menu bar* lives here, because the CLI has no use for
/// it. Collect the whole house, show two numbers.
final class Preferences: ObservableObject {
    /// The bar has room for a few values at most before it starts crowding out
    /// other apps' items.
    static let maxMenuBarItems = 3

    private let defaults: UserDefaults

    @Published var menuBarItems: [MenuBarItem] {
        didSet { save(menuBarItems, forKey: Keys.menuBarItems) }
    }

    /// CO2 thresholds in ppm, for the bar tint and the optional notification.
    @Published var co2Warn: Double {
        didSet { defaults.set(co2Warn, forKey: Keys.co2Warn) }
    }
    @Published var co2Alert: Double {
        didSet { defaults.set(co2Alert, forKey: Keys.co2Alert) }
    }
    @Published var notifyOnCO2: Bool {
        didSet { defaults.set(notifyOnCO2, forKey: Keys.notifyOnCO2) }
    }

    private enum Keys {
        static let menuBarItems = "menuBarItems"
        static let co2Warn = "co2Warn"
        static let co2Alert = "co2Alert"
        static let notifyOnCO2 = "notifyOnCO2"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.menuBarItems = Self.load([MenuBarItem].self, forKey: Keys.menuBarItems, from: defaults) ?? []
        self.co2Warn = defaults.object(forKey: Keys.co2Warn) as? Double ?? 1000
        self.co2Alert = defaults.object(forKey: Keys.co2Alert) as? Double ?? 1500
        self.notifyOnCO2 = defaults.object(forKey: Keys.notifyOnCO2) as? Bool ?? false
    }

    func isOnMenuBar(_ item: MenuBarItem) -> Bool { menuBarItems.contains(item) }

    /// Toggle an item, keeping the list within what the bar can show.
    func toggleMenuBar(_ item: MenuBarItem) {
        if let i = menuBarItems.firstIndex(of: item) {
            menuBarItems.remove(at: i)
        } else if menuBarItems.count < Self.maxMenuBarItems {
            menuBarItems.append(item)
        }
    }

    var isMenuBarFull: Bool { menuBarItems.count >= Self.maxMenuBarItems }

    /// Reorder the bar. The list is ordered, not a set: which reading sits
    /// leftmost is the one seen without looking, so the order is a real choice
    /// and not an accident of the sequence they happened to be ticked in.
    func moveMenuBarItems(from source: IndexSet, to destination: Int) {
        menuBarItems.move(fromOffsets: source, toOffset: destination)
    }

    /// Seed a sensible bar for a first run: the CO2 reading if there is one,
    /// otherwise the first device's temperature. An empty menu bar makes the app
    /// look broken, and picking for the user is easily undone.
    func seedIfEmpty(from readings: [DeviceReading]) {
        guard menuBarItems.isEmpty, !readings.isEmpty else { return }

        if let co2 = readings.first(where: { $0.metrics["co2_ppm"] != nil }) {
            menuBarItems = [
                MenuBarItem(deviceID: co2.deviceID, metric: "temperature_c"),
                MenuBarItem(deviceID: co2.deviceID, metric: "co2_ppm"),
            ]
            return
        }
        if let first = readings.first(where: { $0.metrics["temperature_c"] != nil }) {
            menuBarItems = [MenuBarItem(deviceID: first.deviceID, metric: "temperature_c")]
        }
    }

    /// Drop items whose device is no longer collected, once we know for sure.
    /// Called only with a non-empty device list, so a failed CLI call cannot
    /// silently erase the user's choices.
    func prune(toCollected devices: [Device]) {
        guard !devices.isEmpty else { return }
        let collected = Set(devices.filter(\.enabled).map(\.deviceID))
        let kept = menuBarItems.filter { collected.contains($0.deviceID) }
        if kept.count != menuBarItems.count {
            menuBarItems = kept
        }
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
