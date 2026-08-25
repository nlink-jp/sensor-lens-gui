import AppKit
import SwiftUI

struct SensorLensApp: App {
    @StateObject private var model = Self.makeModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .environmentObject(model.preferences)
        } label: {
            // Both objects, deliberately: the chips are values from the model
            // rendered according to a selection held in preferences, and
            // observing only one of the two leaves the bar stale after the
            // other changes.
            MenuBarLabel(model: model, prefs: model.preferences)
        }
        .menuBarExtraStyle(.window)

        Window("Sensor History", id: "analysis") {
            AnalysisView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentMinSize)

        // A plain Window rather than a Settings scene: an LSUIElement app cannot
        // bring a Settings scene to the front, so its fields never take focus.
        Window("SensorLens Settings", id: "settings") {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.preferences)
                .frame(minWidth: 560, minHeight: 460)
        }
        .windowResizability(.contentMinSize)
    }

    private static func makeModel() -> SensorModel {
        let m = SensorModel()
        m.start()
        return m
    }
}

/// The bar itself: the chosen device × metric chips, tinted by the worst CO2
/// level among them.
///
/// It observes `Preferences` as well as the model. The selection lives in a
/// separate ObservableObject, so without this the bar would not re-render when
/// the user changed it — the new chip would appear only at the next poll, a
/// minute later, which reads as "selecting it did nothing".
struct MenuBarLabel: View {
    @ObservedObject var model: SensorModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        let chips = model.menuBarChips
        if chips.isEmpty {
            Image(systemName: model.isCollecting ? "thermometer.medium" : "thermometer.medium.slash")
        } else {
            HStack(spacing: 6) {
                if let level = model.menuBarCO2Level, level != .ok {
                    Image(systemName: level.symbol)
                }
                // A stale chip keeps its place and is marked, rather than
                // vanishing — a disappearing number reads as a bug.
                Text(chips.map { $0.stale ? "\($0.text)⚠" : $0.text }.joined(separator: "  "))
            }
        }
    }
}

/// Opens one of the app's windows and brings it to the front.
///
/// `openWindow` alone leaves the window behind other apps for an LSUIElement
/// process, because it is not a regular app in the activation order; the
/// explicit activate is what actually shows it.
@MainActor
func openAppWindow(_ id: String, using openWindow: OpenWindowAction) {
    openWindow(id: id)
    NSApp.activate(ignoringOtherApps: true)
}
