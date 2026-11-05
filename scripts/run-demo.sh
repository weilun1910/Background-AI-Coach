#!/bin/bash
# Launches the prototype in demo mode with its own throwaway data folder.
# It starts at onboarding, pretends this is a fresh Mac, and never installs
# anything. Your real settings aren't touched. Everything stays on local
# disk, outside iCloud Drive.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${RECOMMENDER_BUILD_DIR:-$HOME/Library/Developer/Background AI Coach}"
APP="$OUT/Coachmark.app"
[ -d "$APP" ] || ./scripts/build-app.sh

DATA="$OUT/demo-data"
rm -rf "$DATA"
mkdir -p "$DATA"
cat > "$DATA/preferences.json" <<'EOF'
{"demo": {"freshMac": true, "dryRun": true, "ignoreCap": true}}
EOF

pkill -f "/Contents/MacOS/Recommender" || true
sleep 0.5
# `open` makes the app responsible for its own permissions (not Terminal).
open -n --env "RECOMMENDER_DATA_DIR=$DATA" "$APP"
echo "Demo running. Finish onboarding, then click the sparkle in the menu bar and pick Try a moment."
