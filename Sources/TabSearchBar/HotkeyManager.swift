import AppKit
import Carbon
import os

private let log = Logger(subsystem: "com.clearcmos.tabsearch", category: "hotkey")

/// Global Shift+Cmd+F hotkey via Carbon `RegisterEventHotKey`.
///
/// This replaced an earlier CGEvent tap: Terminal's "Secure Keyboard Entry" feature blocks
/// event taps from seeing keystrokes while Terminal is focused, which is exactly when we need
/// the hotkey. A registered Carbon hot key is dispatched by the system and fires regardless,
/// and requires no Accessibility permission.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onHotkey: () -> Void

    init(onHotkey: @escaping () -> Void) {
        self.onHotkey = onHotkey
    }

    @discardableResult
    func start() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                log.notice("Carbon hotkey fired")
                manager.onHotkey()
                return noErr
            },
            1, &spec, selfPtr, &handlerRef)
        guard installStatus == noErr else {
            log.error("InstallEventHandler failed: \(installStatus, privacy: .public)")
            return false
        }

        // 'TSch' signature, arbitrary unique id.
        let hotKeyID = EventHotKeyID(signature: 0x5453_6368, id: 1)
        let modifiers = UInt32(cmdKey | shiftKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_F), modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            log.error("RegisterEventHotKey failed: \(registerStatus, privacy: .public)")
            return false
        }

        log.notice("Carbon hotkey registered (Shift+Cmd+F)")
        return true
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
