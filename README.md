# LaunchSet

A small macOS menu bar app that opens or closes a group of apps with one click, or on a schedule.

Make a group such as "Work" with Slack, Chrome and VS Code. Open the whole group from the menu bar in the morning, or let a schedule do it at 08:30 on weekdays and close it again at 18:00. Before a scheduled close, LaunchSet warns you so you can snooze it or skip it that day.

## Features

- Groups of apps, each with an SF Symbol icon. Add apps from `/Applications`, from the apps that are running, or by dropping `.app` files onto the list. Drag to set the launch order.
- Open or close a group from the menu bar or the manager window. Right-click a group to force quit all of its apps.
- Schedules with a time and days of the week. The app warns about two schedules that open and close the same group at the same time.
- A notification before a scheduled close, with Snooze and Skip. The same buttons show in the menu bar, so they work with notifications turned off.
- Closing works like pressing Command-Q, so apps can still ask you to save. If an app hasn't quit after a timeout, LaunchSet either leaves it open and tells you, or force quits it. You pick per group.
- Missed schedules (the Mac was asleep, or LaunchSet wasn't running) catch up if they are only a few minutes late. Older ones are logged in History.
- History of the last 200 runs, with the result for each app.
- Launch at login, and export or import of the whole configuration as JSON.

LaunchSet never quits Finder, the Dock or other apps macOS needs, even if they appear in a hand-edited config file.

## Requirements

- macOS 14 Sonoma or later
- Swift 6 toolchain. Xcode's Command Line Tools are enough.

## Build and install

```bash
git clone https://github.com/minhdevtree/launchset.git
cd launchset
scripts/build-app.sh --install
```

The script builds a release binary, wraps it in `build/LaunchSet.app`, signs it ad hoc, copies it to `~/Applications` and opens it. Run it without `--install` to only build.

Always run the `.app` bundle. Notifications and Launch at login need a real bundle ID, so `swift run LaunchSet` won't work properly.

## Checks

The scheduling logic lives in `LaunchSetCore`, which only depends on Foundation. `SelfCheck` exercises it without a test framework, since Command Line Tools don't ship XCTest:

```bash
swift run SelfCheck
```

It prints `All checks passed` and exits with 0, or lists the failing checks and exits with 1.

## Why there is no sandbox

The App Sandbox makes `NSRunningApplication.terminate()` return `false` for other apps, so a sandboxed LaunchSet can't close anything. The app runs unsandboxed instead. It doesn't use AppleScript or Apple Events and doesn't ask for Accessibility access.

## Data

Everything lives in `~/Library/Application Support/LaunchSet/`:

- `config.json` holds groups, schedules and settings. It is pretty-printed so you can edit it by hand while the app is closed.
- `history.json` holds the run history.

If `config.json` can't be read, LaunchSet renames it to `config.corrupt-<date>.json`, starts empty and tells you, so the broken file is never overwritten.

## Known limits

- Snooze and skip are kept in memory, so they are forgotten if LaunchSet restarts during a warning.
- Schedules only run while LaunchSet is running. Turn on Launch at login to avoid missing them.

## License

MIT
