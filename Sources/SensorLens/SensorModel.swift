import Foundation
import UserNotifications

/// SensorModel drives the UI and, while the app is running, does the collecting.
///
/// Collection happens by ticking the CLI's `now --if-stale`, which polls only
/// when the stored readings have aged past the interval. That is deliberate: it
/// means this app collects while it is open — halving the API spend against a
/// daemon that runs around the clock — while costing nothing if a daemon is
/// running too. There is no negotiation between the two, and nothing to keep in
/// sync.
@MainActor
final class SensorModel: ObservableObject {
    @Published private(set) var readings: [DeviceReading] = []
    @Published private(set) var devices: [Device] = []
    @Published private(set) var status: Status?
    @Published private(set) var loginItem: LoginItem.State = .disabled
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isBusy = false
    @Published var lastError: String?
    @Published var lastErrorDetail: String?

    /// Recent history for the readings on the menu bar, keyed by MenuBarItem.id.
    /// Drawn in the popover so the number on the bar comes with the shape that
    /// produced it — "22°C" says much less than "22°C and falling".
    @Published private(set) var sparklines: [String: [Bucket]] = [:]

    /// How far back a sparkline reaches, and how coarsely. Six hours covers a
    /// morning or an evening; ten-minute buckets keep it to a few dozen points
    /// whether the data came from 5-minute polling or a 1-minute app export.
    static let sparklineSince = "-6h"
    static let sparklineBucket = "10m"

    // Analysis window state.
    @Published var period = "24h"
    @Published var selectedDevice: String?
    @Published var selectedMetric = "temperature_c"
    @Published private(set) var history: [Reading] = []
    @Published private(set) var gaps: [Gap] = []

    let preferences: Preferences

    private var timer: Timer?
    /// App Nap opt-out token, held for the app's lifetime.
    ///
    /// Without it macOS freezes the timer of a windowless LSUIElement app and
    /// the readings quietly stop updating — a bug claude-usage-lens-gui actually
    /// shipped. Here it would additionally stop collection dead.
    private var activity: NSObjectProtocol?
    private var notifiedHighCO2 = Set<String>()

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
    }

    // MARK: - Lifecycle

    func start() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "collecting sensor readings")

        Task { await self.refresh(force: false) }
        scheduleTimer(seconds: 60)
    }

    /// Re-arm the timer. The tick is deliberately more frequent than the polling
    /// interval: `--if-stale` decides whether a tick actually costs an API call,
    /// so ticking often only makes collection resume promptly after a sleep or a
    /// launch, never more expensive.
    private func scheduleTimer(seconds: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: false) }
        }
        // Added to the *common* run-loop modes, not the default one.
        //
        // `Timer.scheduledTimer` registers for `.default` only, and while a menu
        // or popover is being tracked the run loop leaves that mode — so the
        // readings would freeze for exactly as long as the user held the panel
        // open to look at them. Opening the thing must not stop it updating.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Collecting

    /// One cycle: collect if the data has gone stale, then reload state.
    ///
    /// force skips the staleness check — the Refresh button, where the user has
    /// explicitly asked for a fresh reading and is willing to spend the call.
    func refresh(force: Bool) async {
        if isBusy { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let fresh = try await runOffMain { force ? try CLIRunner.pollNow() : try CLIRunner.tick() }
            let status = try await runOffMain { try CLIRunner.status() }
            let devices = try await runOffMain { try CLIRunner.devices() }

            self.readings = fresh
            self.status = status
            self.devices = devices
            self.lastUpdated = Date()
            self.lastError = nil
            self.lastErrorDetail = nil

            preferences.seedIfEmpty(from: fresh)
            preferences.prune(toCollected: devices)
            checkCO2(fresh)
            // Read rather than remembered: the user can add or remove the login
            // item in System Settings, and a switch that disagrees with the
            // system is worse than no switch.
            refreshLoginItem()
        } catch {
            report(error)
        }
    }

    /// Load the sparklines for whatever is on the bar.
    ///
    /// Called when the popover opens rather than on every tick: it reads the
    /// local database (no API cost) but does spawn a process per series, and
    /// nobody is looking at the result while the popover is shut.
    func loadSparklines() async {
        let items = preferences.menuBarItems
        guard !items.isEmpty else {
            sparklines = [:]
            return
        }
        let since = Self.sparklineSince
        let bucket = Self.sparklineBucket

        var loaded: [String: [Bucket]] = [:]
        for item in items {
            let deviceID = item.deviceID
            let metric = item.metric
            // One failing series must not blank the others; a device with no
            // history yet is a normal state, not an error worth reporting.
            if let series = try? await runOffMain({
                try CLIRunner.historyBuckets(device: deviceID, metric: metric, since: since, bucket: bucket)
            }) {
                loaded[item.id] = series
            }
        }
        sparklines = loaded
    }

    // MARK: - Menu bar

    /// The chips on the bar, in the order the user chose. An item whose device
    /// has stopped reporting keeps its place and is marked stale rather than
    /// vanishing — a chip that disappears reads as a bug, not as a warning.
    var menuBarChips: [(item: MenuBarItem, text: String, stale: Bool)] {
        preferences.menuBarItems.compactMap { item in
            guard let reading = readings.first(where: { $0.deviceID == item.deviceID }),
                  let value = reading.metrics[item.metric] else { return nil }
            return (item, Format.value(item.metric, value), reading.stale)
        }
    }

    /// The worst CO2 anywhere in the house, whichever sensor it came from.
    ///
    /// Not restricted to the bar's own picks: there are three slots and a house
    /// can hold more CO2 meters than that, and a room filling up is worth
    /// showing whether or not that meter won a slot.
    var worstCO2: CO2Reading? {
        CO2Level.worst(readings, warn: preferences.co2Warn, alert: preferences.co2Alert)
    }

    /// The level the menu bar's glyph reflects.
    var menuBarCO2Level: CO2Level? { worstCO2?.level }

    /// True when the CO2 being warned about comes from a sensor that is not one
    /// of the readings on display — in which case the glyph needs explaining.
    var co2AlertIsOffscreen: Bool {
        guard let worst = worstCO2, worst.level != .ok else { return false }
        return !preferences.menuBarItems.contains(
            MenuBarItem(deviceID: worst.deviceID, metric: "co2_ppm"))
    }

    var isCollecting: Bool { status?.collecting ?? false }

    /// Where collection is coming from, said plainly. The app itself counts:
    /// while it is open and no daemon is loaded, its own tick is the collector.
    var collectorDescription: String {
        guard let status else { return "starting…" }
        // Said first: a daemon pointing at a binary that no longer exists looks
        // installed and healthy while collecting nothing at all.
        if status.daemonProgramMissing == true { return "background daemon is broken" }
        if status.daemonLoaded { return "background daemon" }
        if status.collecting { return "this app, while it is running" }
        return "nothing is collecting"
    }

    /// True when the installed daemon points at a binary that has gone.
    var isDaemonBroken: Bool { status?.daemonProgramMissing == true }

    /// Reinstall the daemon so it points at the binary running now.
    func repairDaemon() async {
        await setBackgroundCollection(true)
    }

    // MARK: - Launch at login

    /// Register or unregister the app as a login item.
    ///
    /// With this on and the daemon off, collection covers the whole time the
    /// user is logged in — which for most people is most of the time the room
    /// is worth measuring, at a fraction of a daemon's API spend.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
        } catch {
            lastError = on
                ? "macOS refused to add SensorLens to your login items."
                : "macOS refused to remove SensorLens from your login items."
            lastErrorDetail = error.localizedDescription
        }
        refreshLoginItem()
    }

    func refreshLoginItem() { loginItem = LoginItem.current }

    // MARK: - Background collection toggle

    var isDaemonInstalled: Bool { status?.daemonInstalled ?? false }

    /// Install or remove the LaunchAgent. With it on, collection continues when
    /// the app is closed; with it off, this app is the only collector and there
    /// will be gaps whenever it is not running.
    func setBackgroundCollection(_ on: Bool) async {
        do {
            try await runOffMain { on ? try CLIRunner.install() : try CLIRunner.uninstall() }
            await refresh(force: false)
        } catch {
            report(error)
        }
    }

    // MARK: - Analysis

    func loadAnalysis() async {
        guard let device = selectedDevice ?? devices.first(where: \.enabled)?.deviceID else { return }
        selectedDevice = device
        let since = "-" + period
        let metric = selectedMetric

        do {
            let history = try await runOffMain {
                try CLIRunner.history(device: device, metric: metric, since: since)
            }
            let gaps = try await runOffMain { try CLIRunner.gaps(since: since) }
            self.history = history
            self.gaps = gaps.filter { $0.deviceID == device && $0.metric == metric }
            self.lastError = nil
        } catch {
            report(error)
        }
    }

    /// Metrics this device has actually reported, in reading order.
    func metrics(for deviceID: String) -> [String] {
        guard let r = readings.first(where: { $0.deviceID == deviceID }) else { return [] }
        return Format.sortMetrics(Array(r.metrics.keys))
    }

    // MARK: - CO2 notifications

    /// Notify once per device per crossing into the alert band. Re-notifying
    /// every tick while a room stays stuffy would train the user to ignore it.
    private func checkCO2(_ readings: [DeviceReading]) {
        guard preferences.notifyOnCO2 else {
            notifiedHighCO2.removeAll()
            return
        }
        for r in readings {
            guard let ppm = r.metrics["co2_ppm"], !r.stale else { continue }
            let level = CO2Level.of(ppm, warn: preferences.co2Warn, alert: preferences.co2Alert)
            if level == .high {
                if notifiedHighCO2.insert(r.deviceID).inserted {
                    notify(title: "\(r.name): CO2 \(Int(ppm)) ppm",
                           body: "Above \(Int(preferences.co2Alert)) ppm — worth opening a window.")
                }
            } else if level == .ok {
                notifiedHighCO2.remove(r.deviceID)
            }
        }
    }

    private func notify(title: String, body: String) {
        // The centre is fetched again inside the callback rather than captured:
        // UNUserNotificationCenter is not Sendable, and `current()` is the
        // supported way to reach the same object from wherever the callback runs.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // MARK: - Plumbing

    /// Run CLI work off the main thread. Every call spawns a process and waits;
    /// on the main actor that would stutter the menu bar.
    private nonisolated func runOffMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .utility) { try work() }.value
    }

    private func report(_ error: Error) {
        if let cliError = error as? CLIError {
            lastError = cliError.errorDescription
            lastErrorDetail = cliError.failureReason
        } else {
            lastError = error.localizedDescription
            lastErrorDetail = nil
        }
    }
}
