---
name: launchset-architecture
description: Use when starting any change in the LaunchSet repo, deciding which file or target a change belongs in, tracing how a menu bar click, schedule or launchset command reaches NSWorkspace, or comparing the code with launchset-prompt.md.
---

# LaunchSet architecture

## Overview

LaunchSet is a SwiftPM package with four targets. Pure logic lives in `LaunchSetCore` (Foundation only), the menu bar app is `LaunchSet`, `SelfCheck` exercises Core, and `LaunchSetCLI` is the `launchset` command. All state is owned by `@MainActor` objects created once in `AppDelegate`.

## Map

| File | Owns |
|---|---|
| `LaunchSetCore/Models.swift` | `AppRole`, `AppRef` (custom decode), `AppGroup` + `plan(for:)`, `ScheduleRule`, `AppSettings` defaults, `Config` v1, `RunRecord` (`summary`, `line`, `flash`), `AppOutcome`, `Blocklist`, `JSON` coders |
| `LaunchSetCore/Schedule.swift` | `DueEvent` + `key`, `nextOccurrence`, `upcoming`, `nextRun`, `evaluate`, `conflicts`, weekday and date labels |
| `LaunchSetCore/CLI.swift` | socket path, request/response types, usage text, `table`, socket client and listener |
| `LaunchSet/LaunchSetApp.swift` | scenes (MenuBarExtra, `Window("main")`, Settings), `AppDelegate`, `ViewState` alias, `showsInDock()` |
| `LaunchSet/AppStore.swift` | config and history (load, corrupt-file rename, 0.5 s debounced save), running app set, `run(...)`, add apps, import/export, `confirm`/`showAlert` (NSAlert) |
| `LaunchSet/AppRunner.swift` | single serial queue, open and close per `plan(for:)`, termination wait, busy state |
| `LaunchSet/Scheduler.swift` | 15 s timer and wake/clock observers, `check()`, warnings, snooze, skip, pause, `nextLine`/`nextLabel` |
| `LaunchSet/Notifier.swift` | notification permission, close warning with Snooze/Skip actions |
| `LaunchSet/CommandServer.swift` | Unix socket server behind `launchset` |
| `LaunchSet/Views/*` | MenuBarView, MainWindow, GroupDetailView, ScheduleViews (Table, RuleEditor), HistoryView, SettingsView |

## How a run flows

Menu bar button, manager window, scheduler and CLI all call `AppStore.run(action, groupID:, source:, force:)`. It asks `AppRunner.run`, which chains onto the previous job so commands never overlap, then applies `group.plan(for: action)`: open these apps, quit those. The store appends a `RunRecord` (max 200), refreshes the running set, and sets the 3 s flash for manual runs. `Scheduler.runScheduled` adds notifications for scheduled runs.

Roles decide the plan. Open opens "Open and close" and "Open only" apps and quits "Close on open" apps. Close quits only "Open and close" apps.

## Invariants

- Core never imports AppKit or SwiftUI and never calls `Date()`; callers pass dates and calendars.
- UI state is `@MainActor`. Views read `AppStore` and `Scheduler` from the environment.
- Apps are identified by bundle ID. `Blocklist` apps (Finder, Dock and friends, LaunchSet itself) can't be added and are never quit, even from a hand-edited config.
- Quitting uses `NSRunningApplication.terminate()`/`forceTerminate()`. No sandbox (it makes `terminate()` fail), no AppleScript, no Accessibility.
- `config.json` stays `version: 1`. New fields decode with `decodeIfPresent` and a default, as `AppRef.role` does. Only `AppRef` has a custom `init(from:)` so far; `AppGroup`, `ScheduleRule`, `AppSettings` and `Config` use synthesized decoding, so the first field added to one of them needs a hand-written decoder (and a SelfCheck case that decodes old JSON).
- A config that fails to decode is renamed `config.corrupt-<stamp>.json`, never overwritten.

## Data on disk

`~/Library/Application Support/LaunchSet/`: `config.json`, `history.json`, `cli.sock`. `UserDefaults` domain `local.minhdevtree.launchset` holds `lastCheckedAt`.

## Where launchset-prompt.md is out of date

The spec is the original brief. The owner later changed these, so don't "fix" the code back:

- UI text is English, not Vietnamese.
- Per-app roles and the `launchset` CLI were added (the rest of the spec's out-of-scope list still stands).
- Snooze moves the close to `max(now, planned close) + snooze`, not `now + snooze`.
- Buttons read "Open Group", "Close Group", and the context menu "Force Close…".
- Views use `@ViewState`, not `@State`.

## Related skills

- **launchset-build-and-verify** before claiming anything works.
- **launchset-testing-on-this-mac** before touching the installed app or its data.
- **launchset-scheduling**, **launchset-cli**, **launchset-ui-copy** for those areas.
