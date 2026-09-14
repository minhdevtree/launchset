#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LaunchSet"
APP=build/LaunchSet.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x LaunchSet || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/LaunchSet.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/LaunchSet.app
fi
