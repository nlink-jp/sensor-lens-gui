import AppKit
import UserNotifications

/// Delivering the CO2 warning, and knowing whether it can be delivered at all.
///
/// The permission is asked for when the user switches the notification on, not
/// when the first room finally fills up. Deferring it meant the app never
/// appeared in System Settings → Notifications until an alert happened to fire,
/// so there was nothing to configure and no way to tell whether it would work —
/// a switch promising something unverifiable.
enum Notifications {
    enum Authorization: Equatable {
        /// Never asked. The switch has not been turned on yet.
        case notDetermined
        case allowed
        /// Refused, or turned off later in System Settings. The switch may be
        /// on and still deliver nothing, so this has to be said.
        case denied

        var canDeliver: Bool { self == .allowed }
    }

    static func status() async -> Authorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return map(settings.authorizationStatus)
    }

    /// Ask, and report what the answer was. Asking twice is harmless: macOS
    /// prompts once and returns the standing answer afterwards.
    static func request() async -> Authorization {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert])
        return await status()
    }

    static func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Open the pane where a refusal can be undone.
    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    static func map(_ status: UNAuthorizationStatus) -> Authorization {
        switch status {
        // .ephemeral is iOS-only; provisional delivers quietly and still counts.
        case .authorized, .provisional: return .allowed
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
