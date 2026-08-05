import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: SensorModel
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        VStack(spacing: 8) {
            // Failures from actions taken *here* were only ever shown in the
            // popover, so a switch that refused to move explained itself
            // somewhere the user was not looking.
            if let error = model.lastError {
                ErrorBanner(message: error, detail: model.lastErrorDetail)
            }

            TabView {
                MenuBarSettings().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                CollectionSettings().tabItem { Label("Collection", systemImage: "antenna.radiowaves.left.and.right") }
                AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
            }
        }
        .padding(12)
        // The user can revoke notifications in System Settings at any time, so
        // the state is re-read rather than remembered from when it was granted.
        .task { await model.refreshNotificationAuth() }
    }
}

/// Choosing what appears on the bar — a different, smaller choice than what is
/// collected, made per device × metric so one sensor can contribute only its CO2.
///
/// Two lists rather than one: what is shown, in the order it is shown, and what
/// can be added. A single list of toggles made the order invisible and left the
/// reader working out which of thirty rows were the chosen three.
struct MenuBarSettings: View {
    @EnvironmentObject private var model: SensorModel
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.readings.isEmpty {
                ContentUnavailableView("Nothing collected yet", systemImage: "sensor")
            } else {
                shownSection
                Divider()
                availableSection
            }
        }
    }

    // MARK: - Shown

    private var shownSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("On the menu bar")
                    .font(.headline)
                Text("\(prefs.menuBarItems.count) of \(Preferences.maxMenuBarItems)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("left to right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if prefs.menuBarItems.isEmpty {
                Text("Nothing chosen — add a reading below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                // A plain stack, not a List. It holds at most
                // `maxMenuBarItems` rows, so it never needs to scroll — and a
                // List here has to be given a fixed height, which was smaller
                // than the rows' real height and produced a second scrollbar
                // for three rows that already fitted.
                VStack(spacing: 0) {
                    ForEach(prefs.menuBarItems) { item in
                        if item != prefs.menuBarItems.first {
                            Divider()
                        }
                        shownRow(item)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                    }
                }
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func shownRow(_ item: MenuBarItem) -> some View {
        let index = prefs.menuBarItems.firstIndex(of: item) ?? 0
        return HStack(spacing: 6) {
            Text("\(index + 1).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)

            Text(deviceName(for: item))
                .lineLimit(1)
            Text(Format.label(item.metric))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Buttons rather than drag alone: dragging inside a three-row list
            // is fiddly, and nothing on screen says it is possible.
            Button { prefs.moveMenuBarItem(item, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .disabled(index == 0)
            .help("Move left")

            Button { prefs.moveMenuBarItem(item, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .disabled(index == prefs.menuBarItems.count - 1)
            .help("Move right")

            Button { prefs.remove(item) } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("Remove from the menu bar")
        }
    }

    // MARK: - Available

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Available readings")
                    .font(.headline)
                Spacer()
                if prefs.isMenuBarFull {
                    Text("the menu bar is full — remove one first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            List {
                ForEach(model.readings) { reading in
                    Section {
                        // Identified by device+metric, never by the metric name
                        // alone. A List's ForEach ids must be unique across the
                        // whole list, not within a section, and "temperature_c"
                        // appears under every sensor — so id: \.self made
                        // SwiftUI treat every device's temperature row as the
                        // same row, and acting on one acted on them all.
                        ForEach(MenuBarSettings.rows(for: reading)) { item in
                            availableRow(reading: reading, item: item)
                                .listRowInsets(Self.rowInsets)
                        }
                    } header: {
                        // A plain caption rather than a prominent header: with
                        // thirty devices the default heading turned the list
                        // into mostly headings.
                        Text(reading.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
        }
    }

    private func availableRow(reading: DeviceReading, item: MenuBarItem) -> some View {
        let shown = prefs.isOnMenuBar(item)
        return HStack(spacing: 6) {
            Text(Format.label(item.metric))
                .foregroundStyle(shown ? .secondary : .primary)
            Spacer()
            if let v = reading.metrics[item.metric] {
                Text(Format.bare(item.metric, v))
                    .foregroundStyle(.secondary)
            }
            if shown {
                // Says why the + is gone, instead of leaving a row that simply
                // refuses to respond.
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .help("Already on the menu bar")
            } else {
                Button { prefs.add(item) } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            .focusable(false)
                .disabled(prefs.isMenuBarFull)
                .help(prefs.isMenuBarFull ? "The menu bar is full" : "Add to the menu bar")
            }
        }
    }

    // MARK: - Metrics of the layout itself

    /// Rows are compact deliberately. This pane is a long list of one-line
    /// facts, and at the default row height thirty devices become a scroll
    /// through mostly empty space.
    static let rowHeight: CGFloat = 20
    static let rowInsets = EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8)

    // MARK: - Helpers

    /// The device's name, falling back to its ID. A chosen item can outlive the
    /// reading it came from — a meter offline since launch — and a row that
    /// vanished would look like the setting had been lost.
    private func deviceName(for item: MenuBarItem) -> String {
        if let r = model.readings.first(where: { $0.deviceID == item.deviceID }) { return r.name }
        if let d = model.devices.first(where: { $0.deviceID == item.deviceID }) { return d.name }
        return item.deviceID
    }

    /// The selectable rows for one device, in reading order. Pure, so the
    /// uniqueness their identity depends on can be tested.
    static func rows(for reading: DeviceReading) -> [MenuBarItem] {
        Format.sortMetrics(Array(reading.metrics.keys))
            .map { MenuBarItem(deviceID: reading.deviceID, metric: $0) }
    }
}

struct CollectionSettings: View {
    @EnvironmentObject private var model: SensorModel
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section("Collecting") {
                LabeledContent("Right now", value: model.collectorDescription)

                // Never disabled on the strength of the reported status. macOS
                // says `.notFound` for an app that has simply never registered,
                // which is every app the first time — gating the switch on it
                // made the first attempt the one that could never be made.
                Toggle("Open SensorLens at login", isOn: Binding(
                    get: { model.loginItem == .enabled || model.loginItem == .requiresApproval },
                    set: { on in model.setLaunchAtLogin(on) }
                ))

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
                case .enabled, .notEnabled:
                    Text("Because this app collects while it runs, opening it at login is what keeps the history from having a hole every time the Mac restarts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Keep collecting when this app is closed", isOn: Binding(
                    get: { model.isDaemonInstalled },
                    set: { on in Task { await model.setBackgroundCollection(on) } }
                ))
                if model.isDaemonBroken {
                    // The switch reads "on" and the plist looks healthy, but the
                    // binary it names is gone — usually because this app was
                    // moved or replaced since it was installed.
                    HStack {
                        Text("The background daemon points at a copy of SensorLens that no longer exists.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Repair") { Task { await model.repairDaemon() } }
                            .controlSize(.small)
                    }
                }
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
                // Switching this on asks macOS for permission there and then,
                // which is also what makes the app appear in System Settings →
                // Notifications. Asking only when a room finally filled up left
                // nothing to configure and no way to know it would work.
                Toggle("Notify when a room goes above the high threshold", isOn: Binding(
                    get: { prefs.notifyOnCO2 },
                    set: { on in Task { await model.setNotifyOnCO2(on) } }
                ))

                if model.notificationsBlocked {
                    HStack {
                        Text("macOS is not allowing notifications from SensorLens, so this will not reach you.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Notifications…") { Notifications.openSystemSettings() }
                            .controlSize(.small)
                    }
                } else {
                    HStack {
                        Text("Notified once per room per crossing, not on every reading.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        // "Nothing has crossed the threshold yet" and
                        // "notifications are broken" look identical from
                        // outside. This is what tells them apart.
                        Button("Send a test") { Task { await model.sendTestNotification() } }
                            .controlSize(.small)
                            .disabled(!prefs.notifyOnCO2)
                    }
                }

                // A configuration that cannot ever fire should say so rather
                // than look like a warning system that simply never warns.
                if prefs.notifyOnCO2, let peak = model.alertingCO2Peak, peak.ppm < prefs.co2Alert {
                    Text("Nothing is close to the threshold: the highest reading among the sensors you are watching is \(peak.name) at \(Format.bare("co2_ppm", peak.ppm)), against \(Int(prefs.co2Alert)) ppm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Warn me about") {
                if model.co2Sensors.isEmpty {
                    Text("No CO2 sensor is being collected. Only the Meter Pro CO2 reports it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Which rooms are worth an interruption is the user's call:
                    // a bedroom filling up matters, a server rack may not.
                    ForEach(model.co2Sensors) { sensor in
                        Toggle(isOn: Binding(
                            get: { prefs.alertsOnCO2(from: sensor.deviceID) },
                            set: { prefs.setCO2Alerts($0, for: sensor.deviceID) }
                        )) {
                            HStack {
                                Text(sensor.name)
                                Spacer()
                                if let ppm = sensor.metrics["co2_ppm"] {
                                    Text(Format.bare("co2_ppm", ppm))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("A sensor switched off here still shows its reading — it just stops raising the menu-bar warning and the notification.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
