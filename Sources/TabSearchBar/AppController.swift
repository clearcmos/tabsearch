import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "com.clearcmos.tabsearch", category: "app")

/// Owns the global hotkey and the search panel. Lives for the lifetime of the app.
///
/// The Carbon hot key needs no permission, but the JUMP drives Terminal's Find via synthetic
/// keystrokes (System Events), which requires Accessibility. Granting THIS app (a stable
/// bundle identity) is robust; relying on osascript's own grant proved fragile (it broke when
/// Terminal was restarted for a screen-recording grant).
final class AppController {
    private let panelController = SearchPanelController()
    private var hotkey: HotkeyManager?

    func start() {
        log.notice("AppController.start trusted=\(AXIsProcessTrusted(), privacy: .public)")
        promptAccessibilityIfNeeded()
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

    func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func promptAccessibilityIfNeeded() {
        if !AXIsProcessTrusted() { promptAccessibility() }
    }
}
