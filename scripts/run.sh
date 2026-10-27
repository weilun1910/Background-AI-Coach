#!/bin/bash
# Launches the prototype for real use: your real apps, your real calendar,
# and real installs when you click "Install it for me".
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${RECOMMENDER_BUILD_DIR:-$HOME/Library/Developer/Background AI Coach}"
APP="$OUT/Background AI Coach.app"
[ -d "$APP" ] || ./scripts/build-app.sh

pkill -f "/Contents/MacOS/Recommender" || true
sleep 0.5
open -n "$APP"
echo "Running. Look for the sparkle in the menu bar."
