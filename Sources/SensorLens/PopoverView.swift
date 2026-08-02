import Charts
import SwiftUI

/// The popover shows **what you put on the menu bar**, each with the last six
/// hours behind it.
///
/// It deliberately does not list every collected device. Collecting a whole
/// house is worth doing — it is what makes the history complete — but reading
/// fifteen cards is not what someone wants from a menu-bar click. Everything
/// else stays one click further away: any device in the History window, all of
/// them with current values in Settings.
///
/// Bounded to `Preferences.maxMenuBarItems` rows, so there is no ScrollView and
/// therefore no way for the content to collapse to nothing.
struct PopoverView: View {
    @EnvironmentObject private var model: SensorModel
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let error = model.lastError {
                ErrorBanner(message: error, detail: model.lastErrorDetail)
            }

            if selected.isEmpty {
                EmptyStateView()
            } else {
                VStack(spacing: 8) {
                    ForEach(selected, id: \.item.id) { pair in
                        SparklineRow(item: pair.item, reading: pair.reading,
                                     series: model.sparklines[pair.item.id] ?? [])
                    }
                }
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
        // Loaded when the popover opens, not on every poll: it costs no API
        // calls but does spawn a process per series, and nobody is looking at
        // the result while the popover is shut.
        .task { await model.loadSparklines() }
    }

    /// The menu-bar picks that have a reading to show, in the chosen order.
    private var selected: [(item: MenuBarItem, reading: DeviceReading)] {
        prefs.menuBarItems.compactMap { item in
            guard let reading = model.readings.first(where: { $0.deviceID == item.deviceID }),
                  reading.metrics[item.metric] != nil else { return nil }
            return (item, reading)
        }
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(model.isCollecting ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(model.collectorDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Read the sensors now")
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("History…") { openAppWindow("analysis", using: openWindow) }
                .buttonStyle(.borderless)
            Button("Settings…") { openAppWindow("settings", using: openWindow) }
                .buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
    }
}

/// One menu-bar reading with the last six hours behind it. A number on its own
/// says less than the same number with a direction: "22°C" versus "22°C, and it
/// has been climbing all afternoon".
struct SparklineRow: View {
    @EnvironmentObject private var prefs: Preferences
    let item: MenuBarItem
    let reading: DeviceReading
    let series: [Bucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(reading.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(Format.label(item.metric))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                if let trend {
                    Image(systemName: trend.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .help(trend.help)
                }
                if let value = reading.metrics[item.metric] {
                    Text(Format.bare(item.metric, value))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint(value))
                }
            }

            if series.count >= 2 {
                chart
                HStack {
                    Text(Format.bare(item.metric, low))
                    Spacer()
                    Text("last 6h")
                    Spacer()
                    Text(Format.bare(item.metric, high))
                }
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            } else {
                Text("Not enough history yet")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(height: 20)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }

    private var chart: some View {
        Chart(series) { bucket in
            AreaMark(x: .value("Time", bucket.date), y: .value("Value", bucket.avg))
                .foregroundStyle(.linearGradient(
                    colors: [lineColor.opacity(0.28), lineColor.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", bucket.date), y: .value("Value", bucket.avg))
                .foregroundStyle(lineColor)
                .interpolationMethod(.monotone)
        }
        // A sparkline is a shape, not a reading: the axes would only take room
        // from it, and the exact numbers sit above and below it already.
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .frame(height: 34)
    }

    private var values: [Double] { series.map(\.avg) }
    private var domain: ClosedRange<Double> { Sparkline.domain(values) }
    private var low: Double { values.min() ?? 0 }
    private var high: Double { values.max() ?? 0 }

    private var lineColor: Color {
        guard item.metric == "co2_ppm", let v = reading.metrics["co2_ppm"], !reading.stale else {
            return .accentColor
        }
        return CO2Level.of(v, warn: prefs.co2Warn, alert: prefs.co2Alert).color
    }

    private func tint(_ value: Double) -> Color {
        guard item.metric == "co2_ppm", !reading.stale else { return .primary }
        return CO2Level.of(value, warn: prefs.co2Warn, alert: prefs.co2Alert).color
    }

    private var trend: Sparkline.Trend? { Sparkline.trend(values) }
}

/// Why the popover has nothing to show, and what to do about it. The three
/// causes need three different answers, and "no readings" would be an unhelpful
/// thing to say to someone who simply has not picked any yet.
struct EmptyStateView: View {
    @EnvironmentObject private var model: SensorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .noCredentials:
                Text("No SwitchBot credentials yet.")
                    .font(.system(size: 12, weight: .medium))
                Text("Open Settings and paste the token and secret from the SwitchBot app (Profile → Preferences → tap App Version ten times → Developer Options).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                settingsButton

            case .noReadings:
                Text("No readings yet.")
                    .font(.system(size: 12, weight: .medium))
                Text("Nothing has been collected. Use Refresh above, or check that your sensors are reachable through a SwitchBot hub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .nothingChosen:
                Text("Nothing chosen to show.")
                    .font(.system(size: 12, weight: .medium))
                Text("Pick the readings you want here and on the menu bar — up to \(Preferences.maxMenuBarItems). Every collected sensor is available in the History window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                settingsButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var settingsButton: some View {
        Button("Settings…") { openAppWindow("settings", using: openWindow) }
            .controlSize(.small)
    }

    private enum State { case noCredentials, noReadings, nothingChosen }

    private var state: State {
        if model.status?.hasCredentials == false { return .noCredentials }
        if model.readings.isEmpty { return .noReadings }
        return .nothingChosen
    }
}

struct ErrorBanner: View {
    let message: String
    let detail: String?
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message).font(.caption)
                Spacer()
                if detail?.isEmpty == false {
                    Button(showDetail ? "Less" : "More") { showDetail.toggle() }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
            }
            if showDetail, let detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
