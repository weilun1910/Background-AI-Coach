#!/bin/bash
# Builds the menu-bar app and wraps it in a .app bundle.
# Build output goes to local disk, outside iCloud Drive:
#   ~/Library/Developer/AI Tool Recommender
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
OUT="${RECOMMENDER_BUILD_DIR:-$HOME/Library/Developer/AI Tool Recommender}"
SCRATCH="$OUT/swiftpm"
APP="$OUT/AI Tool Recommender.app"
mkdir -p "$OUT"

swift build -c "$CONFIG" --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c "$CONFIG" --scratch-path "$SCRATCH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Recommender" "$APP/Contents/MacOS/Recommender"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Resources/catalog.json "$APP/Contents/Resources/catalog.json"
cp Resources/personas.json "$APP/Contents/Resources/personas.json"

# Sign with an Apple Development identity when there is one, so macOS keeps
# the calendar permission between rebuilds. Otherwise sign ad hoc.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP" >/dev/null
else
  codesign --force --sign - "$APP" >/dev/null
fi

echo "Built $APP"
