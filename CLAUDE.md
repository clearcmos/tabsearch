# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What This Is

`tabsearch` searches text across all of Apple Terminal.app's tabs and windows, jumps to the
tab, scrolls to the match, and glows a highlight over it. Terminal's built-in Cmd+F only
searches the frontmost tab, and Terminal exposes no plugin/extension API - so this is a
companion app that reads and drives Terminal from the outside via AppleScript and the
Accessibility API.

Modeled on the sibling `blackout` project (same author): a Swift Package Manager macOS tool
shipping a CLI and a SwiftUI menu bar app.

## Build Commands

```bash
make app           # build the menu bar app
make bundle        # build + assemble + sign TabSearch.app (stable cert; see Code signing)
make install-app   # bundle + copy to /Applications  (this is the real product)
make cli           # build the CLI
make install-cli   # copy CLI to /usr/local/bin
make debug         # quick debug build of both
make clean
```

No test target. `tabsearch demo` is the self-test: creates a throwaway window, buries a
marker, searches, jumps/scrolls to it, verifies it became visible, cleans up, prints PASS.
It is keystroke-free, so it passes even from a non-Accessibility context.

## Code signing (important)

The app is signed with a **stable self-signed identity** `tabsearch-codesign` in the login
keychain. A constant signature keeps the app's TCC grants (Accessibility, Automation) stable
across rebuilds. Ad-hoc signing (`--sign -`) changes the signature every build and voided the
grants each time, causing endless re-granting. The Makefile uses this identity and falls back
to ad-hoc if it is absent.

To recreate the identity (e.g. on a new machine):
```bash
openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 3650 -nodes \
  -subj "/CN=tabsearch-codesign" -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -legacy -inkey k.pem -in c.pem -out c.p12 -passout pass:tspass -name "tabsearch-codesign"
security import c.p12 -P tspass -T /usr/bin/codesign     # then rm k.pem c.pem c.p12
```
`-legacy` is required or macOS `security` rejects the p12 ("MAC verification failed").
After a rebuild changes the binary, grants persist; only a NEW cert would require re-granting.

## Architecture

Minimum macOS 13. Three SPM targets in `Package.swift`:

- **TabSearchKit** (library, Foundation only) - the reusable core.
  - `TerminalBridge.swift` - all Terminal interaction:
    - `snapshotAllTabs()` - one AppleScript pass capturing every tab's scrollback (per-window
      try/catch; some windows throw and must be skipped, not abort the whole snapshot).
    - `filter(_:term:)` - pure in-memory line search; records each match's `relativePosition`
      (0..1 for scrolling) and `charOffset` (for AX bounds).
    - `jump(to:)` / `jump(to:relativePosition:)` - raise the tab and scroll via the scroll bar.
    - `listTabs`, `history(of:)`, `contents(of:)`, `search(_:)`, `runDemo()`.
- **tabsearch** (executable) - `main.swift`, hand-rolled args (`list`, `search`, `jump`, `demo`).
- **TabSearchBar** (executable; links AppKit + Carbon, uses ApplicationServices) - the app.
  - `TabSearchBarApp` (MenuBarExtra, accessory) / `AppController` (prompts Accessibility).
  - `HotkeyManager` - Carbon `RegisterEventHotKey` for Shift+Cmd+F.
  - `SearchPanelController` - non-activating floating NSPanel + local key monitor.
  - `SearchModel` / `SearchView` - the search UI; `activateSelection()` jumps then flashes.
  - `MatchOverlay` - the highlight glow window + AX geometry to position it.

## How jump + highlight work (and what was rejected)

- **Scroll** is done by setting the tab's **`AXScrollBar` value** (0=top, 1=bottom) to the
  match's relative position, via System Events. This is keystroke-free, directed at a UI
  element (no leaking into other apps), and Terminal honors it.
- **Highlight** is an external `MatchOverlay` window (borderless, click-through, floating)
  glowed over the matched line. Its rect comes from the AX API: `AXBoundsForRange` for exact
  glyph bounds (with a row-math fallback from `AXVisibleCharacterRange` + uniform row height),
  spanning the text area's full width. AX coords are top-left origin; flip to Cocoa bottom-left.
- **Rejected approaches (do not retry):**
  - Synthetic-keystroke Find (Cmd+F + type + Return): scrolls, but keys go to the FRONTMOST
    app, so any focus race leaks Cmd-keystrokes into Finder/desktop ("opened random things").
    Fragile and unsafe. Replaced by the scroll bar.
  - `AXSelectedTextRange` / `AXVisibleCharacterRange` writes: Terminal accepts them but no-ops
    (no scroll, and AXSelectedText reads back empty - so no real selection, ever). Cmd+J
    ("Jump to Selection") is also ignored. Terminal has NO programmatic text selection; that
    is why the highlight must be an external overlay.

## Permissions

- **Accessibility** (Privacy & Security > Accessibility): required, granted to **TabSearch.app**.
  Used for the scroll (System Events UI scripting) and the overlay's direct AX reads. The
  Carbon hot key itself does NOT need it.
- **Automation**: control Terminal (read tabs, raise) and System Events (scroll). Prompted on
  first use. The app shells to `osascript`; as the responsible process, the app's grants cover
  its osascript children, so the stable cert keeps everything authorized across rebuilds.

## Hard-Won AppleScript Gotchas (do not relearn these)

- `contents of <tabVariable>` fails with -1700: `contents of` is a built-in dereference
  operator that shadows Terminal's `contents` property. Use the full inline specifier
  `get contents of tab N of window id W`. (`history` is not shadowed; inline it anyway.)
- `do script` returns a flaky tab reference. Re-acquire via `selected tab of front window`
  or by `window id`.
- Address windows by stable `id`, not index.
- `snapshotAllTabs` MUST wrap each window in `try`: some windows (certain full-screen TUI
  sessions) throw -10000/-1728 when read, and one failure otherwise aborts the entire search.
- TUI / alternate-screen tabs (Claude Code, vim, less, htop, tmux) expose empty
  `history`/`contents` - only normal command-output scrollback is searchable. Not a bug.
- Hot key MUST be Carbon `RegisterEventHotKey`, not a CGEvent tap: Terminal's "Secure Keyboard
  Entry" (the author keeps it on) blocks event taps from seeing keys while Terminal is focused.
- The search panel must be a `.nonactivatingPanel` floating NSPanel with `canBecomeKey`
  overridden true; an accessory app can't activate itself from a background hot key, so a
  normal window stays invisible/non-key.

## Known rough edges / TODO

- Offsets (`charOffset`, `relativePosition`) come from the snapshot taken when the panel
  opened. If a tab produces output between snapshot and jump, the scroll/overlay can be
  slightly off. Fine for idle scrollback (the usual case).
- Diagnostic `os.Logger` lines (subsystem `com.clearcmos.tabsearch`) are still in; read with
  `/usr/bin/log show --predicate 'subsystem == "com.clearcmos.tabsearch"'`. Quiet once stable.
- Installed as a login item (System Settings > General > Login Items). A LaunchAgent would be
  more robust.
- `TODO.md` holds a deferred plan to give the search panel the macOS 26 Liquid Glass look.
