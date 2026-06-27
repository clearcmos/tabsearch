# tabsearch

Search text across every open tab and window of Apple's built-in Terminal.app, jump to a
match, and highlight it. Terminal's own Find (Cmd+F) only searches the frontmost tab; this
fills that gap.

Apple Terminal has no plugin or extension API, so this is not a plugin. It is a companion
app that reads and drives Terminal from the outside via AppleScript and the Accessibility
API, the only supported way to integrate with Terminal.

## What it is

- A menu bar app (`TabSearchBar` / TabSearch.app) with a global **Shift+Cmd+F** shortcut that
  opens a search panel, searches every tab's scrollback live, and on Enter jumps to the
  matching tab, scrolls to the line, and glows a highlight over it.
- A CLI (`tabsearch`) exposing the same core for scripting and testing.

## How it works

1. Snapshot every Terminal window/tab's scrollback in one AppleScript pass (skipping any
   window that errors, so one bad window doesn't break the search).
2. Filter the snapshot in memory as you type.
3. On selection: raise the tab, scroll to the match by setting the tab's scroll bar position
   via the Accessibility API (no synthetic keystrokes), then draw a brief translucent overlay
   window over the matched line, positioned with `AXBoundsForRange`.

### Known limitation

Tabs running full-screen TUI apps (Claude Code, vim, less, htop, tmux) draw to the terminal's
alternate screen buffer, which Terminal does not expose to AppleScript - their scrollback
reads as empty, so their on-screen content is not searchable. Normal command output is
searched fully.

## Build and install

```bash
make install-app   # build, bundle, sign, and copy TabSearch.app to /Applications
make install-cli   # build and copy the CLI to /usr/local/bin
make debug         # quick debug build
```

The app is signed with a stable self-signed identity so its permissions persist across
rebuilds (see `CLAUDE.md` > Code signing).

## Use

Launch TabSearch.app, then press **Shift+Cmd+F** anywhere, type, navigate with Up/Down, and
press Return to jump. CLI:

```bash
tabsearch list           # list open windows/tabs
tabsearch search foo     # find "foo" across all tabs' scrollback
tabsearch jump foo       # jump to the first match
tabsearch demo           # self-test the round-trip on a throwaway window
```

## Permissions

- **Accessibility** (Privacy & Security > Accessibility): granted to TabSearch.app. Used to
  scroll the tab and position the highlight overlay. The Shift+Cmd+F hot key itself does not
  need it (it is a Carbon hot key, which also works under Terminal's Secure Keyboard Entry).
- **Automation**: to control Terminal (read tabs) and System Events (scroll). Prompted on
  first use.
