import Charts
import SwiftUI

/// The popover shows **every collected device**, not just the ones on the bar.
/// That is the whole point of the split: collect the house, put two numbers on
/// the bar, and look here for the rest.
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

            if model.readings.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        // What is on the bar, with the shape behind the number.
                        ForEach(prefs.menuBarItems) { item in
                            if let reading = model.readings.first(where: { $0.deviceID == item.deviceID }) {
                                SparklineRow(item: item, reading: reading,
                                             series: model.sparklines[item.id] ?? [])
                            }
                        }

                        if !prefs.menuBarItems.isEmpty {
                            Divider().padding(.vertical, 2)
                        }

                        ForEach(model.readings) { reading in
                            DeviceCard(reading: reading)
                        }
                    }
                    .padding(.trailing, 2)
                }
                // An explicit height, not just a maximum.
                //
                // A ScrollView is infinitely flexible, so its *ideal* height is
                // zero — and a MenuBarExtra window sizes itself to its content's
                // ideal size. With only `maxHeight` the whole list collapsed to
                // nothing and the popover showed a header sitting directly on a
                // footer. `PopoverLayout.contentHeight` estimates from the row
                // counts so a short list does not leave a pane of empty space.
                .frame(height: PopoverLayout.contentHeight(
                    sparklines: sparklineCount, devices: model.readings.count))
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

    /// Menu-bar picks that actually have a reading to draw.
    private var sparklineCount: Int {
        prefs.menuBarItems.filter { item in
            model.readings.contains { $0.deviceID == item.deviceID }
        }.count
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

/// One device's current values.
struct DeviceCard: View {
    @EnvironmentObject private var prefs: Preferences
    let reading: DeviceReading

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(reading.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if reading.stale {
                    Label(Format.age(Date().timeIntervalSince(reading.date)), systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("No fresh reading — the device or its hub may be offline")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ForEach(Format.sortMetrics(Array(reading.metrics.keys)), id: \.self) { metric in
                    if let value = reading.metrics[metric] {
                        MetricChip(metric: metric, value: value, stale: reading.stale)
                    }
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct MetricChip: View {
    @EnvironmentObject private var prefs: Preferences
    let metric: String
    let value: Double
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Format.bare(metric, value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(Format.label(metric))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .opacity(stale ? 0.5 : 1)
    }

    /// Only CO2 is tinted. Colouring everything would make the tint mean
    /// nothing; CO2 is the reading with an actionable threshold.
    private var tint: Color {
        guard metric == "co2_ppm", !stale else { return .primary }
        return CO2Level.of(value, warn: prefs.co2Warn, alert: prefs.co2Alert).color
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var model: SensorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.status?.hasCredentials == false {
                Text("No SwitchBot credentials yet.")
                    .font(.system(size: 12, weight: .medium))
                Text("Open Settings and paste the token and secret from the SwitchBot app (Profile → Preferences → tap App Version ten times → Developer Options).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Settings…") { openAppWindow("settings", using: openWindow) }
                    .controlSize(.small)
            } else {
                Text("No readings yet.")
                    .font(.system(size: 12, weight: .medium))
                Text("Nothing has been collected. Use Refresh above, or check that your sensors are reachable through a SwitchBot hub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
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
