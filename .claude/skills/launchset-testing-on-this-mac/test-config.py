#!/usr/bin/env python3
"""Write a throwaway LaunchSet config that only touches TextEdit and Calculator.

    test-config.py <backup-dir> [open+MIN] [close+MIN] [--warn MIN] [--roles]

Refuses to run unless <backup-dir> holds a complete backup from userdata.sh, so the
user's real config can always be restored. Schedules are set MIN minutes from now,
on today's weekday only. --roles makes Calculator "open only" and TextEdit "close on open".
"""
import datetime, json, os, sys, uuid

args = sys.argv[1:]
if not args or not os.path.isfile(os.path.join(args[0], ".complete")):
    sys.exit("Back up first: userdata.sh backup <dir>, then pass that dir as the first argument.")
data = os.environ.get("LAUNCHSET_DATA", os.path.expanduser("~/Library/Application Support/LaunchSet"))
warn = int(args[args.index("--warn") + 1]) if "--warn" in args else 0
roles = "--roles" in args
now = datetime.datetime.now()
weekday = now.isoweekday() % 7 + 1  # Calendar weekday: 1 = Sunday
group_id = str(uuid.uuid4()).upper()

def app(bundle_id, name, path, role):
    return {"bundleID": bundle_id, "name": name, "lastKnownPath": path, "role": role if roles else "openAndClose"}

rules, times = [], []
for arg in args[1:]:
    if "+" not in arg:
        continue
    action, minutes = arg.split("+")
    at = now + datetime.timedelta(minutes=int(minutes))
    rules.append({"id": str(uuid.uuid4()).upper(), "groupID": group_id, "action": action,
                  "hour": at.hour, "minute": at.minute, "weekdays": [weekday], "isEnabled": True})
    times.append(f"{action} {at:%H:%M}")

config = {"version": 1, "rules": rules,
          "groups": [{"id": group_id, "name": "Test", "symbol": "hammer", "launchDelaySeconds": 0,
                      "hideAfterOpen": False, "quitPolicy": "leaveAndNotify",
                      "apps": [app("com.apple.calculator", "Calculator", "/System/Applications/Calculator.app", "openOnly"),
                               app("com.apple.TextEdit", "TextEdit", "/System/Applications/TextEdit.app", "closeOnOpen")]}],
          "settings": {"warnBeforeCloseMinutes": warn, "snoozeMinutes": 10, "quitTimeoutSeconds": 15,
                       "missedGraceMinutes": 15, "notifyOnSuccess": False, "schedulesPaused": False}}
os.makedirs(data, exist_ok=True)
with open(os.path.join(data, "config.json"), "w") as f:
    json.dump(config, f, indent=2)
history = os.path.join(data, "history.json")
if os.path.exists(history):
    os.remove(history)
print(f"Wrote test config at {now:%H:%M:%S}: group Test, {', '.join(times) or 'no schedules'}, warn {warn} min.")
