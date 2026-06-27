import Foundation
import TabSearchKit

let args = Array(CommandLine.arguments.dropFirst())

func usage() {
    print("""
    tabsearch - search text across all macOS Terminal tabs (spike)

    Usage:
      tabsearch list             List all open Terminal windows and tabs
      tabsearch search <term>    Search every tab's scrollback for <term>
      tabsearch jump <term>      Jump to the first tab containing <term> and highlight it
      tabsearch demo             Self-test the read -> select -> highlight round-trip

    Note: tabs running full-screen TUI apps (Claude Code, vim, less, htop, tmux)
    expose no scrollback to AppleScript, so only normal command output is searchable.
    """)
}

do {
    guard let cmd = args.first else { usage(); exit(1) }

    switch cmd {
    case "list":
        let tabs = try TerminalBridge.listTabs()
        if tabs.isEmpty { print("No Terminal windows open."); break }
        for t in tabs {
            print("window \(t.windowIndex) (id \(t.windowID))  tab \(t.tabIndex)  \(t.tty)")
        }

    case "search":
        guard args.count >= 2 else { fputs("usage: tabsearch search <term>\n", stderr); exit(2) }
        let term = args[1]
        let matches = try TerminalBridge.search(term)
        if matches.isEmpty { print("No matches for \"\(term)\" in any tab."); break }
        print("\(matches.count) match(es) for \"\(term)\":\n")
        for m in matches {
            let snippet = m.line.count > 100 ? String(m.line.prefix(100)) + "..." : m.line
            print("  window \(m.tab.windowIndex) tab \(m.tab.tabIndex) (\(m.tab.tty)) line \(m.lineNumber): \(snippet)")
        }

    case "jump":
        guard args.count >= 2 else { fputs("usage: tabsearch jump <term>\n", stderr); exit(2) }
        let term = args[1]
        let matches = try TerminalBridge.search(term)
        guard let first = matches.first else { print("No matches for \"\(term)\"."); break }
        print("Jumping to window \(first.tab.windowIndex) tab \(first.tab.tabIndex) line \(first.lineNumber)...")
        try TerminalBridge.jump(to: first)

    case "demo":
        print("Running read/select/highlight round-trip self-test...\n")
        print(try TerminalBridge.runDemo())

    default:
        usage(); exit(1)
    }
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
