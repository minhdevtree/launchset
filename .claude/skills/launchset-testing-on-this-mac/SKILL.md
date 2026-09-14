---
name: launchset-testing-on-this-mac
description: Use when verifying a LaunchSet change on the real Mac: running the installed app, opening or quitting apps, editing or reading ~/Library/Application Support/LaunchSet, creating test groups or schedules, running launchset open/close/pause, or taking screenshots of the app's UI.
---

# Testing LaunchSet on the real Mac

## Overview

The Mac running this repo is the owner's daily machine, and LaunchSet on it holds their real groups. Those groups quit Terminal, Slack, Chrome, Docker and WebStorm. A careless test can quit the tools you are running in, or erase groups that exist nowhere else. Every real-machine test runs inside a backup, uses only TextEdit and Calculator, and ends with a byte-for-byte restore.

**Violating the letter of these rules is violating their spirit.**

## The rules

1. **Look before you write.** Read `~/Library/Application Support/LaunchSet/` before any test. A config you didn't create belongs to the owner.
2. **Back up, then swap.** `userdata.sh backup <new dir>` first, `test-config.py <that dir> ...` to write a throwaway config, `userdata.sh restore <that dir>` at the end. Never hand-write config.json over the owner's file.
3. **Only TextEdit, Calculator and fixtures you built.** Never open, quit, or force quit anything else, and never run `launchset open/close` on a group the owner made.
4. **Never schedule the owner's groups.** Don't add, enable or trigger schedules on their groups, and don't leave `pause` or `resume` flipped in their config.
5. **Screenshot the app's windows only.** Capture by window ID (`screencapture -l <id>`). Full-screen or other-display captures show the owner's private work.

## Quick reference

| Task | How |
|---|---|
| Back up owner data | `.claude/skills/launchset-testing-on-this-mac/userdata.sh backup "$SCRATCH/lsbackup-1"` |
| Test config with schedules | `test-config.py "$SCRATCH/lsbackup-1" open+2 close+4 --warn 1 [--roles]` |
| Install a build | After the backup: `scripts/build-app.sh --install` (it kills and reopens LaunchSet, so never run it before `userdata.sh backup`) |
| Drive the app without clicks | `launchset open Test`, `launchset status`, `launchset history 5` |
| App that refuses to quit | `quit-blocker.sh "$SCRATCH/qb"`, add its bundle to the test group, `pkill -x QuitBlocker` after |
| Restore | `userdata.sh restore "$SCRATCH/lsbackup-1"` (reopens the app if it was running) |

`$SCRATCH` is your session scratchpad, never the repo.

## Seeing UI you can't click

Nothing opens the manager window from outside. Add a temporary hook in `AppDelegate.applicationDidFinishLaunching`, build, and run the binary **inside the bundle** (a bare `.build` binary crashes on `UNUserNotificationCenter`):

```swift
var previewWindows: [NSWindow] = []   // AppDelegate property, keeps the windows alive
// inside applicationDidFinishLaunching:
if ProcessInfo.processInfo.environment["LS_PREVIEW"] != nil {
    let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = NSHostingView(rootView: MainWindow().environment(store).environment(scheduler))
    w.isReleasedWhenClosed = false; w.center(); w.orderFrontRegardless(); previewWindows.append(w)
    NSLog("PREVIEW \(w.windowNumber)")
}
```

`LS_PREVIEW=1 ~/Applications/LaunchSet.app/Contents/MacOS/LaunchSet > /tmp/ls.log 2>&1 &`, then `screencapture -x -o -l <number from log> out.png` and read the PNG. Swap in `MenuBarView()`, `SettingsView()` or `RuleEditor(rule:)` the same way. Remove the hook before committing (`git diff` must not contain `LS_PREVIEW`).

## Timing and platform traps

- The scheduler ticks every 15 s with 5 s tolerance. Check results at least 20 s after a scheduled minute.
- TextEdit autosaves, so quitting it never shows a save dialog. Use QuitBlocker for "Still open" and force quit paths.
- Calculator quits when its window closes. If it vanishes, someone closed the window; LaunchSet only quits apps it lists in history.
- Alerts can open on a second display. Find LaunchSet's windows with `CGWindowListCopyWindowInfo` filtered by its pid before deciding an alert never appeared.
- `pkill -x LaunchSet` skips `applicationWillTerminate`, so a change made in the last 0.5 s is not saved.
- zsh aborts the whole command when a glob matches nothing (`rm config.corrupt-*.json`). Use `find "$DIR" -name 'config.corrupt-*' -delete`.
- `log show` has nothing useful about app launches or quits here.

## Red flags, stop and back up first

| Thought | Reality |
|---|---|
| "The data folder is empty, I cleared it earlier" | The owner may have used the app since. Look again. |
| "I'll just add a Test group to their config" | Swap the whole file inside a backup instead. |
| "Their group is the real scenario" | Rebuild the scenario with TextEdit and Calculator. |
| "A quick full-screen screenshot is fine" | Capture the window ID only. |
| "Restore can wait until the end of the session" | Restore right after each test. |
