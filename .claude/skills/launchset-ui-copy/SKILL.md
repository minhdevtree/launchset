---
name: launchset-ui-copy
description: Use when writing or changing any user-facing text in LaunchSet (buttons, menu items, alerts, notifications, empty states, history notes, launchset command output, README), or when launchset-prompt.md's Vietnamese strings seem to disagree with the code.
---

# LaunchSet UI copy

## Overview

All user-facing text is English, written inline in Swift (no String Catalog). The owner asked for every string to pass the humanizer skill: plain, specific, no AI tells. The Vietnamese copy in `launchset-prompt.md` is the original brief and is superseded.

**REQUIRED SUB-SKILL:** Use humanizer:humanizer on new or changed strings.

## Rules

| Kind | Case | Examples |
|---|---|---|
| Buttons, menu items, window titles | Title Case (macOS HIG) | `Open Group`, `Skip This Time`, `Force Close…`, `Import and Replace` |
| Labels, messages, notifications, empty states, CLI output | Sentence case | `Wait between app launches`, `Some apps didn't close` |
| Destructive alert buttons | The verb, marked `hasDestructiveAction` | `Delete`, `Force Quit`, never `OK` or `Yes` |

- No em dashes (U+2014) or en dashes (U+2013) anywhere, not even between two days. Write `Weekdays`, or use commas, colons or periods.
- Straight quotes: `"Work"`. An ellipsis `…` goes on items that open a dialog or panel.
- Say what happens and what to do: `TextEdit is still open after 15 seconds. It may be waiting for you to save a file.`
- Singular and plural: `1 app`, `2 apps`. Build the string with a count check, as `Notifier.warn` does.
- Times are 24-hour `HH:mm` from `Schedule.relativeParts`; days are `Today`, `Tomorrow`, a weekday name, or `Sep 25`.
- Contractions are fine (`can't`, `didn't`). No exclamation marks, no "Oops", no "Please".

## Existing phrasing to stay consistent with

- Alerts: title asks or states (`Force quit 4 apps in "Work"?`), message gives the consequence (`Unsaved changes in these apps will be lost.`).
- Empty states: `No groups yet. Create a group to open or close several apps at once.`
- History notes: `Missed the 08:00 schedule (the Mac was asleep or LaunchSet wasn't running)`, `Skipped this time`.
- Roles: `Open and close`, `Open only`, `Close on open`.
- Summaries: `3 closed, 1 still open`; flashes: `Opened 3 of 4 apps`, `Opened 1 of 1, closed 3 of 3`.

## Where strings live

Views in `Sources/LaunchSet/Views/`, alerts in `AppStore.swift`, notifications in `Scheduler.swift` and `Notifier.swift`, CLI text in `CommandServer.swift` and `CLI.usage`, outcome and role labels in `LaunchSetCore/Models.swift`. SelfCheck asserts some of these strings, so update checks together with the text.

## Quick self-check before committing

```bash
perl -CSD -ne 'print "$ARGV:$.: $_" if /[\x{2013}\x{2014}]/; close ARGV if eof' $(git ls-files '*.swift' '*.md' ':!launchset-prompt.md')   # must print nothing (the Vietnamese brief is kept as written)
```
