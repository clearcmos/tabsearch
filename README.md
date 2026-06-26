# tabsearch

Search text across every open tab and window of Apple's built-in Terminal.app, then
jump to a match. Terminal's own Find (Cmd+F) only searches the frontmost tab; this fills
that gap.

Apple Terminal has no plugin or extension API, so this is not a plugin. It is a small
companion tool that reads and drives Terminal from the outside via AppleScript and the
Accessibility/Automation system, the only supported way to integrate with Terminal.

## Status

Early spike. The command-line tool below works and proves the full mechanism end to end.
A menu bar app with a global Shift+Cmd+F shortcut and a search results panel is the next
phase (see `CLAUDE.md`).

## How it works

1. Enumerate all Terminal windows and tabs (AppleScript).
2. Read each tab's scrollback (`history` property) and search it in-process.
3. For a chosen match, select that tab and bring its window to the front
   (`selected` and `frontmost` are writable AppleScript properties).
4. Drive Terminal's native Find to scroll to and highlight the match in that tab.

### Known limitation

Tabs running full-screen TUI apps (Claude Code, vim, less, htop, tmux) draw to the
terminal's alternate screen buffer, which Terminal does not expose to AppleScript. Their
scrollback reads as empty, so their on-screen content is not searchable. Normal command
output is searched fully.

## Build

```bash
make cli                 # release build -> .build/release/tabsearch
make debug               # debug build (faster, for checking compilation)
make install-cli         # copy the binary to /usr/local/bin
```

## Use

```bash
tabsearch list           # list open windows/tabs
tabsearch search foo     # find "foo" across all tabs' scrollback
tabsearch jump foo       # jump to and highlight the first match
tabsearch demo           # self-test the round-trip on a throwaway window
```

## Permissions

- Automation (Privacy and Security > Automation): to control Terminal and System Events.
- Accessibility (Privacy and Security > Accessibility): to drive Terminal's Find via
  synthetic keystrokes (and, later, for the global hotkey).

The spike shells out to `osascript`, so on first run macOS prompts to let your terminal
control Terminal/System Events. The production app will request these as its own bundle.
