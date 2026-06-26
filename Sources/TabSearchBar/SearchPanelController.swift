import AppKit
import SwiftUI
import TabSearchKit
import os

private let log = Logger(subsystem: "com.clearcmos.tabsearch", category: "panel")

/// Borderless panels cannot become key by default, which would block typing. Override.
final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Manages the Spotlight-style floating search panel: showing/hiding, positioning, and the
/// local key monitor for navigation (Up/Down/Return/Esc). Normal typing falls through to the
/// SwiftUI text field.
final class SearchPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let model = SearchModel()
    private var keyMonitor: Any?

    override init() {
        super.init()
        model.onRequestClose = { [weak self] in self?.hide() }
    }

    func toggle() {
        log.notice("toggle (visible=\(self.panel?.isVisible ?? false, privacy: .public))")
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
        installKeyMonitor()
        // Focus the field only after the window is actually key. Bumping during show() (before
        // makeKey takes effect) loses the first-open race and leaves the field unfocused.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.model.requestFocus()
        }
        log.notice("panel shown key=\(panel.isKeyWindow, privacy: .public) frame=\(NSStringFromRect(panel.frame), privacy: .public)")
        model.loadSnapshot()
    }

    private func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        // A non-activating floating panel can be shown and made key WITHOUT activating the
        // app, which is required when triggering from a global hot key while another app
        // (Terminal) is frontmost. An accessory app cannot reliably activate itself there.
        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false  // we always need keyboard input
        panel.animationBehavior = .utilityWindow
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        // .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive; using the former
        // (plus fullScreenAuxiliary so the panel shows over full-screen Terminal windows).
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let host = NSHostingView(rootView: SearchView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 680, height: 420)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + frame.height * 0.62  // upper third, Spotlight-like
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53:            // Esc
                self.hide(); return nil
            case 36, 76:        // Return / Enter
                self.model.activateSelection(); return nil
            case 125:           // Down
                self.model.moveSelection(1); return nil
            case 126:           // Up
                self.model.moveSelection(-1); return nil
            default:
                return event    // let the text field handle normal typing
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide()  // clicking away, cmd-tabbing, or the post-jump activation of Terminal closes it
    }
}
