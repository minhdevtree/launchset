#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP=build/LaunchSet.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN_DIR/LaunchSet" "$APP/Contents/MacOS/"
cp "$BIN_DIR/LaunchSetCLI" "$APP/Contents/Helpers/launchset"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP/Contents/Helpers/launchset"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x LaunchSet || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/LaunchSet.app
  cp -R "$APP" ~/Applications/
  mkdir -p ~/.local/bin
  ln -sf ~/Applications/LaunchSet.app/Contents/Helpers/launchset ~/.local/bin/launchset
  echo "Linked ~/.local/bin/launchset"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "Add ~/.local/bin to PATH to run launchset by name." ;;
  esac
  open ~/Applications/LaunchSet.app
fi
