import Charts
import SwiftUI

/// The history window: one device × metric over time, with the stretches nobody
/// recorded marked rather than smoothed over.
struct AnalysisView: View {
    @EnvironmentObject private var model: SensorModel

    private let periods = ["6h", "24h", "7d", "30d"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls

            if let error = model.lastError {
                ErrorBanner(message: error, detail: model.lastErrorDetail)
            }

            if model.history.isEmpty {
                ContentUnavailableView(
                    "No readings in this range",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Nothing was collected for this period. `sensor-lens gaps` lists what is missing, and an export from the SwitchBot app can fill it in.")
                )
                .frame(maxHeight: .infinity)
            } else {
                chart
                gapsList
            }
        }
        .padding(16)
        .task { await model.loadAnalysis() }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Device", selection: Binding(
                get: { model.selectedDevice ?? "" },
                set: { model.selectedDevice = $0; Task { await model.loadAnalysis() } }
            )) {
                ForEach(model.devices.filter(\.enabled)) { device in
                    Text(device.name).tag(device.deviceID)
                }
            }
            .frame(maxWidth: 220)

            Picker("Metric", selection: Binding(
                get: { model.selectedMetric },
                set: { model.selectedMetric = $0; Task { await model.loadAnalysis() } }
            )) {
                ForEach(availableMetrics, id: \.self) { metric in
                    Text(Format.label(metric)).tag(metric)
                }
            }
            .frame(maxWidth: 180)

            Picker("Range", selection: Binding(
                get: { model.period },
                set: { model.period = $0; Task { await model.loadAnalysis() } }
            )) {
                ForEach(periods, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Spacer()
        }
    }

    private var availableMetrics: [String] {
        guard let device = model.selectedDevice else { return [model.selectedMetric] }
        let found = model.metrics(for: device)
        return found.isEmpty ? [model.selectedMetric] : found
    }

    private var chart: some View {
        Chart {
            ForEach(model.history) { reading in
                LineMark(
                    x: .value("Time", reading.date),
                    y: .value(Format.label(model.selectedMetric), reading.value)
                )
                .interpolationMethod(.monotone)
            }

            // Gaps are drawn, not smoothed over. A line that simply connects
            // across a two-day outage invents data that was never measured.
            ForEach(model.gaps) { gap in
                RectangleMark(
                    xStart: .value("Gap start", gap.startDate),
                    xEnd: .value("Gap end", gap.endDate)
                )
                .foregroundStyle(.gray.opacity(0.18))
            }

            if model.selectedMetric == "co2_ppm" {
                RuleMark(y: .value("Elevated", model.preferences.co2Warn))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.orange.opacity(0.6))
                RuleMark(y: .value("High", model.preferences.co2Alert))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.red.opacity(0.6))
            }
        }
        .chartYAxisLabel(Format.label(model.selectedMetric))
        .frame(minHeight: 260)
    }

    @ViewBuilder
    private var gapsList: some View {
        if model.gaps.isEmpty {
            Label("No gaps in this range", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.gaps.count) gap(s) — the API cannot backfill these; export the window from the SwitchBot app and run `sensor-lens import`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.gaps.prefix(5)) { gap in
                    Text("\(gap.startDate.formatted(date: .abbreviated, time: .shortened)) — \(gap.endDate.formatted(date: .omitted, time: .shortened))  (\(Format.span(gap.endDate.timeIntervalSince(gap.startDate))), ~\(gap.missing) missing)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
