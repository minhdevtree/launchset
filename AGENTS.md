# Working on LaunchSet

LaunchSet is a native macOS menu bar app (Swift 6, SwiftUI, SwiftPM) that opens and closes groups of apps by click, schedule or the `launchset` command. See README.md for what it does.

## Read the matching skill first

Skills live in `.claude/skills/<name>/SKILL.md`. Claude Code loads them by name; other agents should open the file.

| Skill | Read it when |
|---|---|
| `launchset-architecture` | Starting any change, finding where code belongs, comparing with `launchset-prompt.md` |
| `launchset-build-and-verify` | Building, adding checks, hitting toolchain errors, before saying something works |
| `launchset-testing-on-this-mac` | Running the installed app, touching its data, opening or quitting apps, screenshots |
| `launchset-scheduling` | Schedules, warnings, snooze, skip, pause, sleep and DST behavior, the Next line |
| `launchset-cli` | The `launchset` command, the socket server, SSH use |
| `launchset-ui-copy` | Any user-facing text |

## Non-negotiable

- This Mac is the owner's daily machine. Back up `~/Library/Application Support/LaunchSet` before a test, use only TextEdit, Calculator and self-built fixtures, never run or schedule the owner's groups, and restore afterwards (`launchset-testing-on-this-mac`).
- Gate before claiming done: `swift build`, `swift run SelfCheck`, `scripts/build-app.sh`, with real output.
- Use `@ViewState`, not `@State` (Command Line Tools can't expand the macOS 27 SDK's `@State` macro).
- No third-party dependencies, no App Sandbox, no AppleScript or Apple Events, no Accessibility permission.
- Git identity is set per repo (`minhdevtree <minhht.1.2.vn@gmail.com>`); never change the global git config. Remote: github.com/minhdevtree/launchset, branch `main`.
