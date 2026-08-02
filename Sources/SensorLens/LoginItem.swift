import Foundation
import ServiceManagement

/// Registering the app to start at login.
///
/// This matters more here than for most menu-bar apps: while it runs, this app
/// *is* the collector. An app that only starts when the user remembers to open
/// it leaves holes in the history that the SwitchBot API cannot fill afterwards.
enum LoginItem {
    enum State: Equatable {
        /// Registered and starting at login.
        case enabled
        /// Not registered.
        case disabled
        /// Registered, but macOS wants the user to allow it in System Settings.
        /// The switch is on and nothing happens at login until they do, so this
        /// has to be said rather than shown as plain "on".
        case requiresApproval
        /// The system will not register this bundle — most often because it is
        /// running from somewhere temporary rather than /Applications.
        case unavailable
    }

    /// Pure mapping from the system's status, so the states the UI must handle
    /// can be tested without touching the real login-item database.
    static func state(from status: SMAppService.Status) -> State {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    static var current: State { state(from: SMAppService.mainApp.status) }

    /// Register or unregister. Throws so the caller can surface a failure rather
    /// than leaving a switch that silently springs back.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Open the pane where the user can approve a blocked login item.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
