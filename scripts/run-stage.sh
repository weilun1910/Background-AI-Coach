#!/bin/bash
# Launches the full-screen persona demo: a pretend Mac for each made-up
# student, with their apps, calendar and the real card. The arrow keys drive it.
#   Right arrow or space: next beat     Left arrow: back one beat
#   1 to 5: switch persona              R: restart the day
#   N: subtitles on or off              H: key hints on or off
#   Esc: switch between full screen and a window       Cmd+Q: quit
# Nothing on this Mac is read apart from app icons, and nothing gets installed.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${RECOMMENDER_BUILD_DIR:-$HOME/Library/Developer/Background AI Coach}"
APP="$OUT/Background AI Coach.app"
[ -d "$APP" ] || ./scripts/build-app.sh

DATA="$OUT/stage-data"
rm -rf "$DATA"
mkdir -p "$DATA"

pkill -f "/Contents/MacOS/Recommender" || true
sleep 0.5
open -n --env "RECOMMENDER_DATA_DIR=$DATA" "$APP" --args --stage
echo "Full-screen demo running. Press the right arrow to start. Cmd+Q quits."
