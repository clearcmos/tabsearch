import Foundation

/// A reference to one Terminal.app tab. Windows are addressed by their stable `id`
/// (not index) so concurrent open/close of other windows does not shift the target.
public struct TabRef: Equatable {
    public let windowIndex: Int
    public let windowID: Int
    public let tabIndex: Int
    public let tty: String

    public init(windowIndex: Int, windowID: Int, tabIndex: Int, tty: String) {
        self.windowIndex = windowIndex
        self.windowID = windowID
        self.tabIndex = tabIndex
        self.tty = tty
    }
}

/// One matching line found in a tab's scrollback.
public struct SearchMatch {
    public let tab: TabRef
    public let lineNumber: Int        // 1-based line within the scrollback buffer
    public let line: String           // the matching line, trimmed of surrounding whitespace
    public let relativePosition: Double  // 0 (top) .. 1 (bottom): where the line sits, for scrolling
    public let charOffset: Int        // character offset of the line start in the scrollback (for AX bounds)

    public init(tab: TabRef, lineNumber: Int, line: String, relativePosition: Double, charOffset: Int) {
        self.tab = tab
        self.lineNumber = lineNumber
        self.line = line
        self.relativePosition = relativePosition
        self.charOffset = charOffset
    }
}

/// A tab plus a captured copy of its scrollback, taken in a single AppleScript pass.
public struct TabSnapshot {
    public let tab: TabRef
    public let history: String

    public init(tab: TabRef, history: String) {
        self.tab = tab
        self.history = history
    }
}

public enum TerminalError: Error, CustomStringConvertible {
    case osascriptFailed(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .osascriptFailed(let m): return "osascript failed: \(m)"
        case .notFound(let m): return m
        }
    }
}

/// Reads and drives Apple's Terminal.app from the outside.
///
/// SPIKE NOTE: AppleScript is executed by shelling out to /usr/bin/osascript, which
/// reuses osascript's already-granted Automation/Accessibility permissions. The production
/// menu bar app should swap `runAppleScript` for in-process NSAppleScript (or ScriptingBridge)
/// so the permission grants attach to the app's own bundle identity. Everything else in this
/// file is production-shaped and stays the same.
public enum TerminalBridge {

    // MARK: - AppleScript execution

    @discardableResult
    public static func runAppleScript(_ source: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-"]   // read the script from stdin to avoid arg-escaping
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        try proc.run()
        if let data = source.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw TerminalError.osascriptFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }

    /// Escapes a Swift string for embedding inside an AppleScript double-quoted literal.
    static func asLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - Enumeration

    public static func listTabs() throws -> [TabRef] {
        let script = """
        set out to ""
        tell application "Terminal"
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                try
                    set wid to id of w
                    set ti to 0
                    repeat with t in tabs of w
                        set ti to ti + 1
                        set out to out & wi & "|" & wid & "|" & ti & "|" & (tty of t) & linefeed
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
        let raw = try runAppleScript(script)
        var tabs: [TabRef] = []
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4,
                  let wi = Int(parts[0]), let wid = Int(parts[1]), let ti = Int(parts[2]) else { continue }
            tabs.append(TabRef(windowIndex: wi, windowID: wid, tabIndex: ti, tty: String(parts[3])))
        }
        return tabs
    }

    // MARK: - Reading text
    //
    // IMPORTANT: read `contents`/`history` via the FULL inline specifier
    // (`... of tab N of window id W`), never `contents of <tabVariable>`. AppleScript's
    // built-in `contents of` dereference operator shadows Terminal's `contents` property
    // when the right side is a plain variable, which fails with error -1700.

    public static func history(of tab: TabRef) throws -> String {
        let script = "tell application \"Terminal\" to get history of tab \(tab.tabIndex) of window id \(tab.windowID)"
        return try runAppleScript(script)
    }

    public static func contents(of tab: TabRef) throws -> String {
        let script = "tell application \"Terminal\" to get contents of tab \(tab.tabIndex) of window id \(tab.windowID)"
        return try runAppleScript(script)
    }

    // MARK: - Snapshot + search

    /// One AppleScript round-trip that captures every tab plus its full scrollback. Take a
    /// snapshot once (when the search panel opens) and filter it in memory as the user types,
    /// rather than re-reading Terminal on every keystroke.
    public static func snapshotAllTabs() throws -> [TabSnapshot] {
        // RS (0x1E) separates fields, GS (0x1D) separates tabs. These control characters do
        // not occur in normal terminal output, so they are safe delimiters.
        let script = """
        set rs to (character id 30)
        set gs to (character id 29)
        set out to ""
        tell application "Terminal"
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                -- Per-window try: some windows (e.g. certain full-screen TUI sessions) throw
                -- -10000/-1728 when their tabs/history are read. Skip them instead of letting
                -- one bad window abort the entire snapshot (which left search finding nothing).
                try
                    set wid to id of w
                    set ti to 0
                    repeat with t in tabs of w
                        set ti to ti + 1
                        try
                            set out to out & wi & rs & wid & rs & ti & rs & (tty of t) & rs & (history of tab ti of window id wid) & gs
                        end try
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
        let raw = try runAppleScript(script)
        let gs = "\u{1D}"
        let rs = "\u{1E}"
        var snapshots: [TabSnapshot] = []
        for record in raw.components(separatedBy: gs) where !record.isEmpty {
            let parts = record.components(separatedBy: rs)
            guard parts.count >= 5,
                  let wi = Int(parts[0]), let wid = Int(parts[1]), let ti = Int(parts[2]) else { continue }
            let tab = TabRef(windowIndex: wi, windowID: wid, tabIndex: ti, tty: parts[3])
            let history = parts[4...].joined(separator: rs)  // rejoin in case output itself contained RS
            snapshots.append(TabSnapshot(tab: tab, history: history))
        }
        return snapshots
    }

    /// Pure in-memory line search over a snapshot. Cheap enough to run on every keystroke.
    public static func filter(_ snapshots: [TabSnapshot], term: String, caseInsensitive: Bool = true) -> [SearchMatch] {
        guard !term.isEmpty else { return [] }
        let needle = caseInsensitive ? term.lowercased() : term
        var matches: [SearchMatch] = []
        for snap in snapshots where !snap.history.isEmpty {
            let normalized = snap.history
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let total = Double(max(normalized.count, 1))
            var offset = 0
            for (idx, rawLine) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(rawLine)
                let hay = caseInsensitive ? line.lowercased() : line
                if hay.contains(needle) {
                    matches.append(SearchMatch(
                        tab: snap.tab,
                        lineNumber: idx + 1,
                        line: line.trimmingCharacters(in: .whitespaces),
                        relativePosition: Double(offset) / total,
                        charOffset: offset
                    ))
                }
                offset += line.count + 1  // +1 for the newline split() removed
            }
        }
        return matches
    }

    public static func search(_ term: String, caseInsensitive: Bool = true) throws -> [SearchMatch] {
        filter(try snapshotAllTabs(), term: term, caseInsensitive: caseInsensitive)
    }

    // MARK: - Jump
    //
    // Select the tab + raise its window via AppleScript (both properties are read/write),
    // then drive Terminal's NATIVE Find (Cmd+F, type the term, Return, Esc) via System Events.
    // Terminal's own find is what scrolls the match into view and highlights it.
    //
    // Production refinement: set the system Find pasteboard (NSPasteboard(.find)) and send
    // Cmd+G instead of synthetically typing arbitrary search text.

    /// Bring the tab to the front and scroll its scrollback to `relativePosition`
    /// (0 = top, 1 = bottom) by setting the scroll bar's accessibility value.
    ///
    /// This is keystroke-free: it cannot leak keys into another app, needs no find bar, and is
    /// directed at a specific UI element rather than the frontmost app. Terminal honors AXValue
    /// writes on its scroll bar and scrolls accordingly (unlike AXSelectedTextRange, which it
    /// accepts but no-ops). Requires Accessibility (UI scripting), which the app holds.
    public static func jump(to tab: TabRef, relativePosition: Double) throws {
        let rel = max(0.0, min(1.0, relativePosition))
        let script = """
        tell application "Terminal"
            set frontmost of window id \(tab.windowID) to true
            set selected of tab \(tab.tabIndex) of window id \(tab.windowID) to true
            activate
        end tell
        tell application "System Events"
            tell process "Terminal"
                try
                    set value of scroll bar 1 of scroll area 1 of splitter group 1 of front window to \(rel)
                end try
            end tell
        end tell
        """
        try runAppleScript(script)
    }

    /// Jump to a specific search result: raise its tab and scroll to where the match sits in
    /// that tab's scrollback.
    public static func jump(to match: SearchMatch) throws {
        try jump(to: match.tab, relativePosition: match.relativePosition)
    }

    // MARK: - Self-test (the spike)
    //
    // Creates a throwaway window with a marker buried under filler so it is scrolled
    // off-screen, runs the full search -> select -> highlight pipeline, verifies the marker
    // became visible (i.e. Terminal scrolled to it), then closes the window.

    public static func runDemo() throws -> String {
        let marker = "TABSEARCH_DEMO_MARKER_42"

        let create = """
        tell application "Terminal"
            do script "clear; echo \(marker); for i in $(seq 1 150); do echo filler-line-$i; done"
            return id of front window
        end tell
        """
        let widStr = try runAppleScript(create).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let wid = Int(widStr) else {
            throw TerminalError.notFound("could not determine test window id (got \"\(widStr)\")")
        }
        Thread.sleep(forTimeInterval: 1.5)  // let the shell loop finish

        defer {
            let close = """
            tell application "Terminal"
                try
                    close (every window whose id is \(wid)) saving no
                end try
            end tell
            """
            _ = try? runAppleScript(close)
        }

        let tab = TabRef(windowIndex: 0, windowID: wid, tabIndex: 1, tty: "")
        var report: [String] = []

        let hist = try history(of: tab)
        let inHistory = hist.contains(marker)
        report.append("1. read scrollback: \(hist.count) chars; marker in history: \(inHistory)")

        let before = try contents(of: tab).contains(marker)
        report.append("2. marker visible BEFORE jump: \(before)  (expect false)")

        let found = try search(marker).filter { $0.tab.windowID == wid }
        report.append("3. search() matches in test window: \(found.count)")

        if let target = found.first {
            try jump(to: target)
        }
        Thread.sleep(forTimeInterval: 0.6)
        let after = try contents(of: tab).contains(marker)
        report.append("4. marker visible AFTER jump: \(after)  (expect true)")

        let pass = inHistory && !before && !found.isEmpty && after
        report.append("")
        report.append(pass ? "RESULT: PASS - full read/select/highlight round-trip works"
                           : "RESULT: FAIL - see steps above")
        return report.joined(separator: "\n")
    }
}
