---
name: launchset-scheduling
description: Use when changing or debugging LaunchSet schedules: runs that fire twice, never, late or after sleep, missed-run history, close warnings, snooze, skip, pause and resume, the menu bar "Next:" line, daylight saving time, or adding any time-based feature.
---

# LaunchSet scheduling

## Overview

The scheduler scans instead of arming timers per rule. `Scheduler.check()` asks the pure `Schedule.evaluate` which events fell in `(lastCheckedAt, now]` and acts on them. That one path handles sleep, clock changes and time zone changes. New time logic goes into `LaunchSetCore/Schedule.swift` as a pure function with `now` and `calendar` parameters, plus checks in SelfCheck.

## When check() runs

- A `Timer` every 15 s, 5 s tolerance, in `.common` run loop mode, so open menus don't block it.
- `NSWorkspace.didWakeNotification`, `.NSSystemClockDidChange`, `.NSSystemTimeZoneDidChange`.
- At launch, `lastCheckedAt = max(saved value, now - missedGraceMinutes)`. A run missed while LaunchSet was off catches up only within grace and is otherwise not logged.

## What check() does

1. Paused: set `lastCheckedAt = now`, drop warnings, stop.
2. Clock went backwards (`now < lastCheckedAt`): set `lastCheckedAt = now`, stop.
3. `evaluate` returns `due` (late by at most grace) and `missed` (run events later than grace). Only the latest event per (rule, kind) counts, so three days asleep give one event.
4. `lastCheckedAt = now` is saved **before** any run starts, so an overlapping `check()` can't run the same event twice.
5. `missed` becomes a history note: `Missed the 18:00 schedule (the Mac was asleep or LaunchSet wasn't running)`.
6. For each due event:
   - `warn` (Close rules, `warnBeforeCloseMinutes` early): ignored if the close time already passed, the group quits nothing, or it was skipped. Otherwise it adds a `Warning` and posts the notification.
   - `run`: a skipped key writes `Skipped this time`. A snoozed key waits. Anything else is queued.
7. Warnings whose `closeAt` passed are removed. Snoozed ones (`closeAt > occurrence`) run a close if the rule is still enabled.
8. Queued runs go through `AppStore.run` in one `Task`, in order.

## Snooze, skip, keys

- Key: `DueEvent.key(ruleID:occurrence:)` = rule UUID + original time. It is the notification ID too.
- Snooze: `closeAt = max(now, closeAt) + snoozeMinutes`. It can repeat and never moves a close earlier.
- Skip: removes the warning. Before the original time the key goes into `skipped` and the run event logs the skip. After it (while snoozed) the skip is logged at once.
- Snooze and skip live in memory only and are lost on restart.
- Pausing clears warnings. `setPaused(false)` sets `lastCheckedAt = now`, so nothing from the paused period catches up.

## Next run labels

`Scheduler.nextLine` and `nextLabel` call `Schedule.upcoming`/`nextRun` with the scheduler's `skipped` set and snoozed close times. A skipped run is passed over and a snoozed close shows its new time. Don't compute next runs from `nextOccurrence` alone in UI or CLI code.

## Calendar rules

- `Calendar.current`. Weekdays use Calendar numbering: 1 = Sunday ... 7 = Saturday. Display order is `Schedule.displayWeekdays` (Monday first).
- `nextDate(... matchingPolicy: .nextTime, repeatedTimePolicy: .first)`: a 02:30 that doesn't exist on the DST day runs at the next valid time that day, and a repeated 01:30 runs once.
- `latestOccurrence` scans at most 8 days back, since a weekly rule always has a run in that span.

## Common mistakes

| Mistake | Fix |
|---|---|
| Calling `Date()` inside Core | Take `now` as a parameter |
| Setting `lastCheckedAt` after awaiting runs | Set it before queuing work |
| Warning for a group whose Close quits nothing | Check `group.plan(for: .close).quit` |
| Assuming a scheduled Open never quits apps | "Close on open" apps quit, without a warning today |
| Testing with a real clock and guessing | Add SelfCheck cases with fixed dates; on the Mac, wait 20 s past the minute |
