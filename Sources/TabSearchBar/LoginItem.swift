import ServiceManagement
import os

private let log = Logger(subsystem: "com.clearcmos.tabsearch", category: "loginitem")

/// Manages "launch at login" by registering THIS app bundle via SMAppService. Modern,
/// permission-free, user-toggleable, and shown correctly under System Settings > Login Items.
/// Preferred over scripting a legacy login item (which needs an Automation grant).
enum LoginItem {
    /// On if registered - whether already enabled or pending the user's approval in Settings.
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                let status = SMAppService.mainApp.status
                log.notice("register -> status=\(name(status), privacy: .public)")
                // Newly registered items can land in "requires approval"; send the user to the
                // Login Items pane to flip it on (no-op if it's already enabled).
                if status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
                log.notice("unregister -> status=\(name(SMAppService.mainApp.status), privacy: .public)")
            }
        } catch {
            log.error("login item toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func name(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notRegistered: return "notRegistered"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }
}
