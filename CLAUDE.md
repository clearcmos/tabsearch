# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What This Is

`tabsearch` searches text across all of Apple Terminal.app's tabs and windows and jumps to
a match. Terminal's built-in Cmd+F only searches the frontmost tab. Terminal exposes no
plugin/extension API, so this is a companion tool that reads and drives Terminal from the
outside via AppleScript plus the Accessibility/Automation system.

It is modeled on the sibling `blackout` project (same author): a Swift Package Manager
macOS tool shipping both a CLI and a SwiftUI menu bar app.

## Build Commands

```bash
make cli       # build the CLI (swift build -c release --product tabsearch)
make app       # build the menu bar app
make bundle    # build + assemble + ad-hoc sign TabSearch.app
make debug     # debug build of both, to verify compilation quickly
make install-cli   # copy CLI to /usr/local/bin
make install-app   # copy TabSearch.app to /Applications
make clean
```

No test target. `tabsearch demo` is the self-test: it runs the full round-trip against a
throwaway window and prints PASS/FAIL.

## Architecture

Minimum macOS 13. Three SPM targets in `Package.swift`:

- **TabSearchKit** (library, Foundation only, no UI) - the reusable core, shared by the CLI
  and the app.
  - `TerminalBridge.swift` - all Terminal interaction: `listTabs`, `snapshotAllTabs` (one
    AppleScript pass capturing every tab's scrollback), `filter` (pure in-memory line
    search), `history(of:)`, `contents(of:)`, `search(_:)`, `jump(to:term:)`, `runDemo()`.
- **tabsearch** (executable, depends on TabSearchKit) - `main.swift`, hand-rolled arg
  parsing (`list`, `search`, `jump`, `demo`).
- **TabSearchBar** (executable, depends on TabSearchKit; links AppKit + Carbon) - the menu
  bar app. `TabSearchBarApp` (MenuBarExtra, accessory), `AppController`, `HotkeyManager`
  (Carbon hot key), `SearchPanelController` (non-activating floating NSPanel + key monitor),
  `SearchModel`, `SearchView`.

## Hard-Won AppleScript Gotchas (do not relearn these)

- `contents of <tabVariable>` fails with error -1700. `contents of` is a built-in
  AppleScript dereference operator that shadows Terminal's `contents` property when the
  right side is a plain variable. ALWAYS use the full inline specifier:
  `get contents of tab N of window id W`. (`history` is not shadowed, but inline it too.)
- `do script` returns a flaky tab reference; `contents/history of (do script result)`
  errors. Re-acquire the tab via `selected tab of front window` or by `window id`.
- Address windows by their stable `id`, not by index, so other windows opening/closing
  does not move the target.
- Tabs running full-screen / alternate-screen TUI apps (Claude Code, vim, less, htop,
  tmux) expose empty `history`/`contents`. This is a Terminal limitation, not a bug.
  Only normal command-output scrollback is searchable.
- The global hot key MUST be a Carbon `RegisterEventHotKey`, NOT a CGEvent tap. Terminal's
  "Secure Keyboard Entry" (which the author keeps on) blocks CGEvent taps from seeing keys
  while Terminal is focused - exactly when the hot key is needed. Carbon hot keys are
  dispatched by the system and fire regardless, and require no Accessibility.
- The search panel must be a `.nonactivatingPanel` floating `NSPanel` with `canBecomeKey`
  overridden to true, shown via `makeKeyAndOrderFront` + `orderFrontRegardless` + `makeKey`.
  An accessory (LSUIElement) app cannot activate itself from a background hot key on modern
  macOS, so a normal window stays invisible and non-key; the non-activating panel shows and
  takes focus without activating the app.

## AppleScript execution and the jump

- `TerminalBridge.runAppleScript` shells out to `/usr/bin/osascript`. This is deliberate:
  the app's Carbon hot key needs no Accessibility, so the app itself needs no TCC grant,
  while osascript carries its own (already granted) Automation + Accessibility permissions
  for reading tabs and driving the jump. Moving to in-process `NSAppleScript` would attach
  grants to the app's bundle identity but risks background-thread Apple Event hangs;
  deferred deliberately.
- The jump drives Terminal's native Find (Cmd+F, type term, Return, Esc) via System Events,
  which scrolls to and highlights the match. Secure Keyboard Entry does NOT block this
  (synthetic posting still works; it only blocks event-tap reading). Possible refinement:
  set the system Find pasteboard (`NSPasteboard(.find)`) + Cmd+G to avoid typing the term.

## Permissions

- The app itself needs NO TCC grant (Carbon hot key + non-activating panel).
- osascript needs Automation (control Terminal + System Events) and Accessibility (to post
  the Find keystrokes). Granted once to osascript and persistent - they do NOT reset when
  the app is rebuilt, which is why rebuilds no longer require re-authorizing anything.

## What's built

- TabSearchKit core: `snapshotAllTabs` (one AppleScript pass), in-memory `filter`, and
  `jump` (proven end to end by `tabsearch demo`).
- `tabsearch` CLI: `list`, `search`, `jump`, `demo`.
- `TabSearchBar` menu bar app (LSUIElement, `MenuBarExtra`); `make bundle` -> TabSearch.app.
  - Global Shift+Cmd+F via Carbon `RegisterEventHotKey` (`HotkeyManager`). Works under
    Terminal Secure Keyboard Entry and needs no Accessibility.
  - Spotlight-style non-activating floating `NSPanel` hosting a SwiftUI view: snapshot on
    open, live in-memory filter, focus re-asserted per open, Up/Down navigate, Return jumps,
    Esc closes, click-away dismisses.

## Known rough edges / TODO

- Jump types the term into Terminal's Find, so if the term occurs multiple times in the
  target tab it lands on the first occurrence, not necessarily the picked line. Fix with the
  Find pasteboard + Cmd+G, or AX `AXSelectedTextRange` to the exact offset.
- Diagnostic `os.Logger` lines (subsystem `com.clearcmos.tabsearch`) are still in; read with
  `/usr/bin/log show --predicate 'subsystem == "com.clearcmos.tabsearch"'`. Quiet them once
  the app has proven stable in daily use.
- Not a login item yet; relaunch after reboot, or add it under System Settings > General >
  Login Items, or ship a LaunchAgent.
- Snapshot reads the full scrollback of every tab on each open (fine in practice; cap the
  per-tab length if a tab ever has a huge buffer).
