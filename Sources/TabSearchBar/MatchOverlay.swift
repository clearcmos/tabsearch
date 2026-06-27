import AppKit
import ApplicationServices
import TabSearchKit
import os

private let log = Logger(subsystem: "com.clearcmos.tabsearch", category: "overlay")

/// Briefly glows a translucent highlight over the matched line in Terminal, positioned via the
/// Accessibility API. The window is borderless, click-through, and floating, so it only
/// decorates the screen - it never takes focus or intercepts input.
final class MatchOverlay {
    static let shared = MatchOverlay()
    private var panel: NSPanel?

    /// Locate the matched line on screen and flash a glow over it. Call on the main thread,
    /// after the jump has scrolled the match into view.
    func flash(for match: SearchMatch) {
        guard let rect = Self.lineScreenRect(for: match) else {
            log.notice("overlay: could not locate match rect")
            return
        }
        show(at: rect)
    }

    // MARK: - Overlay window

    private func show(at rect: NSRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(rect.insetBy(dx: -3, dy: -2), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.9
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0.0
            }, completionHandler: { [weak panel] in
                panel?.orderOut(nil)
            })
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = GlowView()
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        return panel
    }

    // MARK: - AX geometry

    /// Screen rect (Cocoa, bottom-left origin) of the matched line, or nil if it can't be found.
    static func lineScreenRect(for match: SearchMatch) -> CGRect? {
        guard let term = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.Terminal").first else {
            log.notice("rect: Terminal not running"); return nil
        }
        let axApp = AXUIElementCreateApplication(term.processIdentifier)
        guard let textArea = focusedTextArea(of: axApp) else { log.notice("rect: no AXTextArea"); return nil }
        guard let taPos = axPoint(textArea, kAXPositionAttribute),
              let taSize = axSize(textArea, kAXSizeAttribute) else { log.notice("rect: no pos/size"); return nil }

        // Preferred: exact glyph bounds for the line via the parameterized attribute. Span the
        // full text-area width so the glow reads as a row highlight.
        let topLeft: CGRect
        if let bounds = axBoundsForRange(textArea, location: match.charOffset, length: 1), bounds.height > 0 {
            topLeft = CGRect(x: taPos.x, y: bounds.origin.y, width: taSize.width, height: bounds.height)
            log.notice("rect: AXBoundsForRange y=\(bounds.origin.y, privacy: .public) h=\(bounds.height, privacy: .public)")
        } else if let fb = fallbackRect(textArea: textArea, taPos: taPos, taSize: taSize, charOffset: match.charOffset) {
            topLeft = fb
            log.notice("rect: fallback y=\(fb.origin.y, privacy: .public) h=\(fb.height, privacy: .public)")
        } else {
            log.notice("rect: no bounds, no fallback"); return nil
        }
        let cocoa = cocoaRect(fromTopLeft: topLeft)
        log.notice("rect: cocoa=\(NSStringFromRect(cocoa), privacy: .public)")
        return cocoa
    }

    private static func focusedTextArea(of axApp: AXUIElement) -> AXUIElement? {
        let window = axElement(axApp, kAXFocusedWindowAttribute) ?? axElement(axApp, kAXMainWindowAttribute)
        guard let window else { return nil }
        return firstDescendant(of: window, role: kAXTextAreaRole)
    }

    private static func firstDescendant(of element: AXUIElement, role: String, depth: Int = 0) -> AXUIElement? {
        if depth > 12 { return nil }
        if axString(element, kAXRoleAttribute) == role { return element }
        guard let children = axChildren(element) else { return nil }
        for child in children {
            if let found = firstDescendant(of: child, role: role, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func axBoundsForRange(_ element: AXUIElement, location: Int, length: Int) -> CGRect? {
        var range = CFRange(location: location, length: length)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &result)
        guard err == .success, let value = result, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Fallback when AXBoundsForRange is unavailable: derive the row from the visible character
    /// range and a uniform row height. Exact for a monospace grid unless a line soft-wraps.
    private static func fallbackRect(textArea: AXUIElement, taPos: CGPoint, taSize: CGSize, charOffset: Int) -> CGRect? {
        guard let value = axString(textArea, kAXValueAttribute),
              let vis = axRange(textArea, kAXVisibleCharacterRangeAttribute) else { return nil }
        let chars = Array(value.utf16)
        guard charOffset >= vis.location, charOffset <= chars.count else { return nil }
        let newline = UInt16(10)
        var row = 0
        var i = vis.location
        while i < charOffset && i < chars.count { if chars[i] == newline { row += 1 }; i += 1 }
        var visibleRows = 1
        var j = vis.location
        let visEnd = min(vis.location + vis.length, chars.count)
        while j < visEnd { if chars[j] == newline { visibleRows += 1 }; j += 1 }
        let rowHeight = taSize.height / CGFloat(max(visibleRows, 1))
        return CGRect(x: taPos.x, y: taPos.y + CGFloat(row) * rowHeight, width: taSize.width, height: rowHeight)
    }

    // MARK: - Coordinate conversion

    /// AX uses a top-left origin on the primary display; Cocoa uses bottom-left. Flip globally.
    private static func cocoaRect(fromTopLeft r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.origin.x, y: primaryHeight - r.origin.y - r.height, width: r.width, height: r.height)
    }

    // MARK: - AX attribute helpers

    private static func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func axChildren(_ el: AXUIElement) -> [AXUIElement]? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success else { return nil }
        return v as? [AXUIElement]
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v else { return nil }
        return v as? String
    }

    private static func axPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let v = axValue(el, attr) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    private static func axSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
        guard let v = axValue(el, attr) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v, .cgSize, &s) ? s : nil
    }

    private static func axRange(_ el: AXUIElement, _ attr: String) -> CFRange? {
        guard let v = axValue(el, attr) else { return nil }
        var r = CFRange(location: 0, length: 0)
        return AXValueGetValue(v, .cfRange, &r) ? r : nil
    }

    private static func axValue(_ el: AXUIElement, _ attr: String) -> AXValue? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }
}

/// Draws the translucent highlighter glow.
private final class GlowView: NSView {
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.systemYellow.withAlphaComponent(0.25).setFill()
        path.fill()
        path.lineWidth = 2
        NSColor.systemYellow.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}
