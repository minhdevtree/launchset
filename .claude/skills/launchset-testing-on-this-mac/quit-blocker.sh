#!/bin/bash
# Build QuitBlocker.app, a menu-bar-less fixture that refuses every normal quit (terminate()).
# Use it to test "Still open" and force quit paths without risking a real app.
#   quit-blocker.sh <dir>   builds <dir>/QuitBlocker.app, bundle ID local.minhdevtree.quitblocker
set -euo pipefail
dir="${1:?usage: $0 <dir>}"
app="$dir/QuitBlocker.app"
mkdir -p "$app/Contents/MacOS"
cat > "$dir/blocker.swift" <<'SWIFT'
import AppKit
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}
let delegate = Delegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
SWIFT
swiftc -O "$dir/blocker.swift" -o "$app/Contents/MacOS/QuitBlocker"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuitBlocker</string>
<key>CFBundleIdentifier</key><string>local.minhdevtree.quitblocker</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app" 2>/dev/null
echo "Built $app. Add it to a test group as {\"bundleID\": \"local.minhdevtree.quitblocker\", \"name\": \"QuitBlocker\", \"lastKnownPath\": \"$app\"}; clean up with: pkill -x QuitBlocker"
