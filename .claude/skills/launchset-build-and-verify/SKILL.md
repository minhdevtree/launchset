---
name: launchset-build-and-verify
description: Use when building LaunchSet, adding tests, before saying a LaunchSet change works, or on build errors such as "external macro implementation type 'SwiftUIMacros.StateMacro' could not be found", "pattern that the region-based isolation checker does not understand", "no such module XCTest", or ld "search path ... not found" warnings.
---

# Building and verifying LaunchSet

## Overview

The machine has Xcode Command Line Tools only (Swift 6.4, macOS 27 SDK), no Xcode. Several normal habits fail here. A change is done when all three gate commands pass on a clean build and the behavior was seen on the installed app.

## The gate

Run from the repo root and report the real output:

```bash
rm -rf .build build
swift build                 # no errors, no Swift warnings
swift run SelfCheck         # prints "All checks passed", exit 0
scripts/build-app.sh        # prints "Built build/LaunchSet.app"
```

Warnings `ld: warning: search path '/Library/Developer/CommandLineTools/...' not found` come from the toolchain and are expected. Any Swift warning is not.

`scripts/build-app.sh --install` also kills the running LaunchSet, copies the app to `~/Applications`, links `~/.local/bin/launchset` and reopens it. That restarts the owner's app, so follow **launchset-testing-on-this-mac** first.

## Toolchain traps

| Symptom | Cause | Do this |
|---|---|---|
| `SwiftUIMacros.StateMacro could not be found` | The macOS 27 SDK makes `@State` a macro, and Command Line Tools lack its plugin | Write `@ViewState` (alias in `LaunchSetApp.swift`). `@Binding`, `@Environment`, `@Bindable`, `@Observable` are fine. |
| `swift test` fails, no XCTest | Not shipped with Command Line Tools | Add `check(cond, "name")` lines to `Sources/SelfCheck/main.swift` |
| `region-based isolation checker does not understand` | `for await` inside `withTaskGroup.addTask` | Race a waiter `Task` against a timer `Task` that cancels it (see `AppRunner.waitUntilGone`) |
| `defaultLaunchBehavior` or other API "only available in macOS 15" | Target is macOS 14 | Find a macOS 14 path |
| Notifications or Launch at login do nothing, or a crash in `UNUserNotificationCenter` | App run outside its bundle (`swift run LaunchSet`, `.build/.../LaunchSet`) | Run `build/LaunchSet.app` or the copy in `~/Applications` |
| An `NSAlert.runModal()` shown at launch closes by itself | Called inside `applicationDidFinishLaunching` while SwiftUI builds scenes | Wrap it in `Task { ... }` |

## What SelfCheck must cover

Every piece of branching logic in `LaunchSetCore` gets checks with fixed dates: `Calendar(identifier: .gregorian)` set to `Asia/Ho_Chi_Minh` (DST cases use `America/New_York`). 2026-09-18 is a Friday. Keep the numbered style and add new checks near related ones. App-target code (AppRunner, Scheduler, CommandServer) can't be imported by SelfCheck, so push logic into Core when it needs a check, as `Schedule.upcoming` does for the Next line.

## Done means

1. Gate output pasted, not paraphrased.
2. The behavior observed on the installed app (history entries, `launchset status`, or a window-ID screenshot), following **launchset-testing-on-this-mac**.
3. README updated when behavior or commands changed.
4. Committed with the local identity (`minhdevtree <minhht.1.2.vn@gmail.com>`, never `git config --global`) and pushed to `origin main` (github.com/minhdevtree/launchset).
