import Foundation

// Codable mirrors of the sensor-lens CLI's --json output. The CLI is the single
// source of truth for polling, storage and aggregation; nothing here recomputes
// what it already decided.

/// One device on the account, and whether it is being collected.
struct Device: Codable, Identifiable, Hashable {
    let deviceID: String
    let name: String
    let deviceType: String
    let hubDeviceID: String?
    let version: String?
    let enabled: Bool
    let firstSeen: Int64
    let lastSeen: Int64

    var id: String { deviceID }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case name
        case deviceType = "device_type"
        case hubDeviceID = "hub_device_id"
        case version
        case enabled
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
    }
}

/// A device's current values, as `now --json` reports them.
struct DeviceReading: Codable, Identifiable, Hashable {
    let deviceID: String
    let name: String
    let deviceType: String
    let metrics: [String: Double]
    let ts: Int64
    /// Stale means nothing has reported for this device recently — the CLI
    /// judges it against the polling interval, so the app never re-derives it.
    let stale: Bool

    var id: String { deviceID }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case name
        case deviceType = "device_type"
        case metrics, ts, stale
    }
}

/// The engine's overall state.
struct Status: Codable {
    let cliVersion: String
    let dbPath: String
    let configPath: String
    let daemonKind: String?
    let daemonLoaded: Bool
    let daemonInstalled: Bool
    let intervalSeconds: Int
    let devices: Int
    let collected: Int
    let readings: Int64
    let lastReadingTS: Int64
    let stale: Bool
    /// Whether readings are arriving at all — judged by data freshness, not by
    /// whether the LaunchAgent is loaded. This app collects while it runs, so an
    /// indicator keyed on launchd would call its own work "not collecting".
    let collecting: Bool
    let callsToday: Int
    let dailyBudget: Int
    let projectedCallsPerDay: Int
    let hasCredentials: Bool

    enum CodingKeys: String, CodingKey {
        case cliVersion = "cli_version"
        case dbPath = "db_path"
        case configPath = "config_path"
        case daemonKind = "daemon_kind"
        case daemonLoaded = "daemon_loaded"
        case daemonInstalled = "daemon_installed"
        case intervalSeconds = "interval_seconds"
        case devices, collected, readings
        case lastReadingTS = "last_reading_ts"
        case stale, collecting
        case callsToday = "calls_today"
        case dailyBudget = "daily_budget"
        case projectedCallsPerDay = "projected_calls_per_day"
        case hasCredentials = "has_credentials"
    }
}

/// One stored measurement.
struct Reading: Codable, Identifiable, Hashable {
    let deviceID: String
    let metric: String
    let ts: Int64
    let value: Double

    var id: String { "\(deviceID)/\(metric)/\(ts)" }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case metric, ts, value
    }
}

/// A stretch with no readings — what an app export could fill back in.
struct Gap: Codable, Identifiable, Hashable {
    let deviceID: String
    let metric: String
    let start: Int64
    let end: Int64
    let missing: Int

    var id: String { "\(deviceID)/\(metric)/\(start)" }
    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(start)) }
    var endDate: Date { Date(timeIntervalSince1970: TimeInterval(end)) }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case metric, start, end, missing
    }
}

/// One metric of one device over a range.
struct Summary: Codable, Identifiable, Hashable {
    let deviceID: String
    let metric: String
    let count: Int
    let min: Double
    let max: Double
    let avg: Double

    var id: String { "\(deviceID)/\(metric)" }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case metric, count, min, max, avg
    }
}

/// A device × metric chosen for the menu bar. The choice belongs to this app —
/// the CLI has no use for it — so it lives in UserDefaults, not config.toml.
struct MenuBarItem: Codable, Identifiable, Hashable {
    let deviceID: String
    let metric: String

    var id: String { "\(deviceID)/\(metric)" }
}
