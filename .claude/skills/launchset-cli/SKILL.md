---
name: launchset-cli
description: Use when adding or changing a launchset command, debugging "LaunchSet isn't running" or empty output from the command line, working on CommandServer or the Unix socket, or helping someone drive LaunchSet over SSH.
---

# The launchset command

## Overview

`launchset` (target `LaunchSetCLI`) doesn't open or quit apps itself. It sends its arguments as JSON to the running app over `~/Library/Application Support/LaunchSet/cli.sock` and prints the reply. `CommandServer` runs the command on the main actor through the same `AppStore`, `AppRunner` and `Scheduler` as the UI, so a command can't race a click and every run lands in History. A process started from SSH isn't in the GUI session and can't manage apps reliably. The app is.

## Protocol

- Request `CLIRequest { args: [String] }`, client writes it then shuts down its write side.
- Reply `CLIResponse { output: String, exitCode: Int32 }`, then the server closes.
- Exit codes: `0` success, `1` the run finished with a failed app (not found, failed to open, still open) or the app isn't reachable, `2` usage error (unknown command, missing or unknown group, bad flag). A command that finds nothing to change still exits `0` and says so, like `close` on a group with nothing to quit (`No apps to close`).
- The client prints `output` to stdout on 0, otherwise to stderr.

## Safety already in place (keep it)

- Socket file mode 0600, and `getpeereid` must match the app's uid.
- `SO_NOSIGPIPE` on each client socket. Without it, a user pressing Ctrl-C during `launchset close` kills LaunchSet with SIGPIPE.
- 5 s receive timeout so a stuck client can't hold a thread.
- `makeListener` unlinks a stale socket from a crashed run.
- `--force` on the command line is the confirmation. Never show an `NSAlert` for a CLI request: nobody may be at the screen.

## Adding a command

1. `Sources/LaunchSetCore/CLI.swift`: add a line to `usage` (help works while the app is closed).
2. `Sources/LaunchSet/CommandServer.swift`: add a `case` in `handle(_:)`. Resolve group names with `find(_:)`, which joins words, ignores case and reports missing or duplicate names. Return `fail(...)` for usage errors.
3. Mutate through `AppStore` or `Scheduler` methods so saving, history and UI refresh stay in one place. When a change affects pending warnings (disabling rules, deleting a group), clear the matching `scheduler.warnings` too, or a dead "Closing soon" line stays in the menu bar.
4. Format output with `CLI.table` and existing labels (`RunRecord.line`, `runningLabel`, `scheduler.nextLabel`). Text follows **launchset-ui-copy**.
5. README "Command line" section.
6. Add a SelfCheck case for any new pure helper in Core.

## Testing

The server only changes when the app is rebuilt and reinstalled, and that restarts the owner's app, so follow **launchset-testing-on-this-mac**: back up, install, test on the throwaway Test group with TextEdit and Calculator, restore. Also check the offline path: with LaunchSet stopped, `build/LaunchSet.app/Contents/Helpers/launchset status` must print the "isn't running" hint and exit 1.

## Install and SSH notes

- `scripts/build-app.sh` places the binary at `LaunchSet.app/Contents/Helpers/launchset` (lowercase names can't sit next to `MacOS/LaunchSet` on a case-insensitive disk) and signs it before the app.
- `--install` links `~/.local/bin/launchset`.
- `ssh mac launchset` runs a shell that may skip `~/.zprofile`; `ssh mac ~/.local/bin/launchset` always works.
- LaunchSet must be running in the owner's logged-in session. Launch at login covers reboots.
