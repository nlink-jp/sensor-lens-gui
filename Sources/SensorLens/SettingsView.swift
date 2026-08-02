import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: SensorModel
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        TabView {
            MenuBarSettings().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            CollectionSettings().tabItem { Label("Collection", systemImage: "antenna.radiowaves.left.and.right") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(16)
    }
}

/// Choosing what appears on the bar — a different, smaller choice than what is
/// collected, made per device × metric so one sensor can contribute only its CO2.
struct MenuBarSettings: View {
    @EnvironmentObject private var model: SensorModel
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick up to \(Preferences.maxMenuBarItems) readings for the menu bar. Everything collected stays visible in the popover.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.readings.isEmpty {
                ContentUnavailableView("Nothing collected yet", systemImage: "sensor")
            } else {
                List {
                    ForEach(model.readings) { reading in
                        Section(reading.name) {
                            // Identified by device+metric, never by the metric
                            // name alone. A List's ForEach ids must be unique
                            // across the whole list, not within a section, and
                            // "temperature_c" appears under every sensor — so
                            // id: \.self made SwiftUI treat every device's
                            // temperature row as the same row, and checking one
                            // checked them all.
                            ForEach(MenuBarSettings.rows(for: reading)) { item in
                                row(reading: reading, item: item)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    /// The selectable rows for one device, in reading order. Pure, so the
    /// uniqueness their identity depends on can be tested.
    static func rows(for reading: DeviceReading) -> [MenuBarItem] {
        Format.sortMetrics(Array(reading.metrics.keys))
            .map { MenuBarItem(deviceID: reading.deviceID, metric: $0) }
    }

    private func row(reading: DeviceReading, item: MenuBarItem) -> some View {
        // Read through the binding rather than capturing a snapshot, so the
        // toggle reflects the store rather than whatever was true when this
        // view was last built.
        let binding = Binding(
            get: { prefs.isOnMenuBar(item) },
            set: { _ in prefs.toggleMenuBar(item) }
        )
        return Toggle(isOn: binding) {
            HStack {
                Text(Format.label(item.metric))
                Spacer()
                if let v = reading.metrics[item.metric] {
                    Text(Format.bare(item.metric, v)).foregroundStyle(.secondary)
                }
            }
        }
        // Full is a limit, not a failure: the already-chosen items stay toggleable.
        .disabled(!prefs.isOnMenuBar(item) && prefs.isMenuBarFull)
    }
}

struct CollectionSettings: View {
    @EnvironmentObject private var model: SensorModel
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section("Collecting") {
                LabeledContent("Right now", value: model.collectorDescription)

                Toggle("Open SensorLens at login", isOn: Binding(
                    get: { model.loginItem == .enabled || model.loginItem == .requiresApproval },
                    set: { on in model.setLaunchAtLogin(on) }
                ))
                .disabled(model.loginItem == .unavailable)

                switch model.loginItem {
                case .requiresApproval:
                    // The switch is on but nothing will happen at login until
                    // the user allows it, so saying only "on" would be a lie.
                    HStack {
                        Text("macOS is waiting for you to allow this.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Login Items…") { LoginItem.openSystemSettings() }
                            .controlSize(.small)
                    }
                case .unavailable:
                    Text("macOS will not register this copy — move SensorLens into your Applications folder and try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .enabled, .disabled:
                    Text("Because this app collects while it runs, opening it at login is what keeps the history from having a hole every time the Mac restarts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Keep collecting when this app is closed", isOn: Binding(
                    get: { model.isDaemonInstalled },
                    set: { on in Task { await model.setBackgroundCollection(on) } }
                ))
                Text(model.isDaemonInstalled
                     ? "A background daemon collects around the clock. This app's own polling then costs nothing, because it only polls when the readings have gone stale."
                     : "Readings are collected only while this app is running. Whatever happens while it is closed cannot be recovered from the API — it can only be imported from a SwitchBot app export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API usage today") {
                if let s = model.status {
                    LabeledContent("Calls today", value: "\(s.callsToday) of \(s.dailyBudget) budgeted")
                    LabeledContent("If left running", value: "\(s.projectedCallsPerDay) per day")
                    LabeledContent("Devices collected", value: "\(s.collected) of \(s.devices)")
                    LabeledContent("Polling interval", value: "\(s.intervalSeconds)s")
                    Text("The account's limit is 10,000 calls a day. Past it the API answers \"Unauthorized\", which looks exactly like a wrong token — which is why the budget sits below the limit. Change the interval or the collected devices in config.toml.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for the engine…").foregroundStyle(.secondary)
                }
            }

            Section("CO2 thresholds") {
                Stepper("Elevated above \(Int(prefs.co2Warn)) ppm", value: $prefs.co2Warn, in: 400...5000, step: 100)
                Stepper("High above \(Int(prefs.co2Alert)) ppm", value: $prefs.co2Alert, in: 400...5000, step: 100)
                Toggle("Notify when a room goes above the high threshold", isOn: $prefs.notifyOnCO2)
                Text("Notified once per room per crossing, not on every reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettings: View {
    @EnvironmentObject private var model: SensorModel

    /// The app's own version, shown because a screenshot of a bug is useless
    /// without knowing which build produced it.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section("Versions") {
                LabeledContent("SensorLens", value: appVersion)
                LabeledContent("sensor-lens engine", value: model.status?.cliVersion ?? "—")
            }
            Section("Files") {
                if let s = model.status {
                    LabeledContent("Database", value: s.dbPath)
                    LabeledContent("Configuration", value: s.configPath)
                }
                Text("Credentials live in the configuration file, readable only by you. This app never stores them itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Setting up credentials") {
                Text("In the SwitchBot app: Profile → Preferences → tap \"App Version\" ten times → Developer Options → Get Token. Put the token and secret in the configuration file above under [switchbot], then use Refresh.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
    }
}
