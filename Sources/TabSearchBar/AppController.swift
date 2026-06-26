import AppKit
import os

private let log = Logger(subsystem: "com.clearcmos.tabsearch", category: "app")

/// Owns the global hotkey and the search panel. Lives for the lifetime of the app.
///
/// The Carbon hot key needs no Accessibility permission, so there is nothing to prompt for
/// or poll. Reading tabs and jumping go through osascript, which carries its own (already
/// granted) Automation/Accessibility permissions.
final class AppController {
    private let panelController = SearchPanelController()
    private var hotkey: HotkeyManager?

    func start() {
        log.notice("AppController.start")
        let hk = HotkeyManager { [weak self] in self?.panelController.toggle() }
        if hk.start() {
            hotkey = hk
        } else {
            log.error("hotkey registration failed")
        }
    }

    func toggle() {
        panelController.toggle()
    }
}
