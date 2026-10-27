#!/bin/bash
# Launches the persona demo: the same app on a pretend Mac. Pick a persona,
# then click Next moment to play their day. Nothing on this Mac is read and
# nothing gets installed. Data stays on local disk, outside iCloud Drive.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${RECOMMENDER_BUILD_DIR:-$HOME/Library/Developer/Background AI Coach}"
APP="$OUT/Background AI Coach.app"
[ -d "$APP" ] || ./scripts/build-app.sh

DATA="$OUT/persona-data"
rm -rf "$DATA"
mkdir -p "$DATA"

pkill -f "/Contents/MacOS/Recommender" || true
sleep 0.5
open -n --env "RECOMMENDER_DATA_DIR=$DATA" "$APP" --args --personas
echo "Persona demo running. Use the window on the left. Cards show up in the top-right corner."
