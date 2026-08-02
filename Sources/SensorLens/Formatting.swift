import Foundation
import SwiftUI

/// Rendering rules for metric values, mirroring the CLI's `cmd/format.go`. Pure,
/// so a test can hold the two in lockstep.
enum Format {
    struct Unit {
        let label: String       // short name for a legend or a settings row
        let suffix: String
        let precision: Int
        /// prefix disambiguates a value that would be meaningless bare on a line
        /// with others — two unlabelled percentages, or an illuminance of "1".
        let prefix: String
    }

    static let units: [String: Unit] = [
        "temperature_c": Unit(label: "Temperature", suffix: "°C", precision: 1, prefix: ""),
        "humidity_pct": Unit(label: "Humidity", suffix: "%", precision: 0, prefix: ""),
        "co2_ppm": Unit(label: "CO2", suffix: " ppm", precision: 0, prefix: ""),
        "battery_pct": Unit(label: "Battery", suffix: "%", precision: 0, prefix: "bat "),
        "light_level": Unit(label: "Light", suffix: "", precision: 0, prefix: "light "),
        "move_detected": Unit(label: "Motion", suffix: "", precision: 0, prefix: "motion "),
        "dew_point_c": Unit(label: "Dew point", suffix: "°C", precision: 1, prefix: "dew "),
        "vpd_kpa": Unit(label: "VPD", suffix: " kPa", precision: 2, prefix: "vpd "),
        "absolute_humidity_gm3": Unit(label: "Absolute humidity", suffix: " g/m³", precision: 1, prefix: "abs "),
    ]

    /// The reading order a person uses: how it feels, then the air, then the
    /// housekeeping.
    static let preferredOrder = ["temperature_c", "humidity_pct", "co2_ppm", "light_level", "battery_pct"]

    static func label(_ metric: String) -> String {
        units[metric]?.label ?? metric
    }

    /// Full rendering, prefix included — for a line that mixes metrics.
    static func value(_ metric: String, _ v: Double) -> String {
        guard let u = units[metric] else { return "\(metric)=\(trimmed(v))" }
        return u.prefix + String(format: "%.\(u.precision)f", v) + u.suffix
    }

    /// Rendering without the disambiguating prefix — for somewhere the metric is
    /// already named, such as a chart axis or a labelled row.
    static func bare(_ metric: String, _ v: Double) -> String {
        guard let u = units[metric] else { return trimmed(v) }
        return String(format: "%.\(u.precision)f", v) + u.suffix
    }

    static func sortMetrics(_ metrics: [String]) -> [String] {
        let rank = Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { ($1, $0) })
        return metrics.sorted { a, b in
            switch (rank[a], rank[b]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a < b
            }
        }
    }

    /// "3m ago" / "2h 10m ago" — for the age of a reading.
    static func age(_ seconds: TimeInterval) -> String {
        let s = Int(abs(seconds))
        switch s {
        case ..<60: return "\(s)s ago"
        case ..<3600: return "\(s / 60)m ago"
        case ..<86400: return "\(s / 3600)h \((s % 3600) / 60)m ago"
        default: return "\(s / 86400)d \((s % 86400) / 3600)h ago"
        }
    }

    static func span(_ seconds: TimeInterval) -> String {
        let s = Int(abs(seconds))
        switch s {
        case ..<60: return "\(s)s"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h \((s % 3600) / 60)m"
        default: return "\(s / 86400)d \((s % 86400) / 3600)h"
        }
    }

    private static func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

/// CO2 bands. Below 1000 ppm is ordinary indoor air; 1000–1500 is the range
/// where people report drowsiness and poorer concentration; above that is a
/// clear signal to open a window. The thresholds are configurable because the
/// right number depends on the room and who is in it.
enum CO2Level {
    case ok, elevated, high

    static func of(_ ppm: Double, warn: Double, alert: Double) -> CO2Level {
        if ppm >= alert { return .high }
        if ppm >= warn { return .elevated }
        return .ok
    }

    var color: Color {
        switch self {
        case .ok: return .green
        case .elevated: return .orange
        case .high: return .red
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "aqi.low"
        case .elevated: return "aqi.medium"
        case .high: return "aqi.high"
        }
    }

    /// The worst CO2 reading anywhere, and which room it came from.
    ///
    /// Deliberately over *every* collected sensor, not just the ones chosen for
    /// the menu bar. There are only three slots and a house can have more CO2
    /// meters than that; a room filling up is a fact about the house, not a
    /// property of what someone happened to put on the bar. Naming the room is
    /// part of the same point — with several sensors, "CO2 is high" without
    /// saying where is not actionable.
    ///
    /// Stale readings are skipped: a number from a meter that stopped reporting
    /// hours ago says nothing about the air now.
    static func worst(_ readings: [DeviceReading], warn: Double, alert: Double) -> CO2Reading? {
        readings
            .filter { !$0.stale }
            .compactMap { r -> CO2Reading? in
                guard let ppm = r.metrics["co2_ppm"] else { return nil }
                return CO2Reading(deviceID: r.deviceID, name: r.name, ppm: ppm,
                                  level: CO2Level.of(ppm, warn: warn, alert: alert))
            }
            .max { $0.ppm < $1.ppm }
    }
}

/// One sensor's CO2, with the band it falls in.
struct CO2Reading: Equatable {
    let deviceID: String
    let name: String
    let ppm: Double
    let level: CO2Level
}
