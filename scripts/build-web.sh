#!/bin/bash
# Builds the web walkthrough of the full-screen demo, for sending to testers.
# It renders every step of the demo from the real app without the presenter
# notes, keeps the frames the walkthrough uses, and copies the page in.
# Output goes to local disk, outside iCloud Drive:
#   ~/Library/Developer/Background AI Coach/web-dist
# To put it online, run this from that folder once you've logged in to Vercel:
#   npx vercel deploy --prod
# SKIP_RENDER=1 reuses the last frames, for when only the page, captions or
# survey changed. WEB_NAME=<name> builds into web-dist-<name> and
# web-frames-<name> instead, to preview a change without touching the folder
# that's linked to Vercel.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${RECOMMENDER_BUILD_DIR:-$HOME/Library/Developer/Background AI Coach}"
APP="$OUT/Background AI Coach.app"
SUFFIX="${WEB_NAME:+-$WEB_NAME}"
RAW="$OUT/web-frames$SUFFIX"
DATA="$OUT/web-data$SUFFIX"
DIST="$OUT/web-dist$SUFFIX"

if [ "${SKIP_RENDER:-}" = 1 ] && [ -f "$RAW/beats.txt" ]; then
  echo "Reusing the frames in $RAW"
else
  ./scripts/build-app.sh
  rm -rf "$RAW" "$DATA"
  mkdir -p "$RAW" "$DATA"
  RECOMMENDER_DATA_DIR="$DATA" "$APP/Contents/MacOS/Recommender" --stage-test --render "$RAW" --clean > "$RAW/beats.txt"
fi

# Keep the Vercel project link (.vercel) between builds and replace the rest.
mkdir -p "$DIST"
find "$DIST" -mindepth 1 -maxdepth 1 ! -name .vercel -exec rm -rf {} +
mkdir -p "$DIST/frames"

python3 -I web/build.py "$RAW/beats.txt" Resources/personas.json web/captions.json "$DIST/walkthrough.json"
while read -r frame; do
  [ -f "$DIST/frames/$frame" ] && continue
  sips -Z 2000 -s format jpeg -s formatOptions 74 "$RAW/${frame%.jpg}.png" --out "$DIST/frames/$frame" >/dev/null
done < "$DIST/frames.txt"
rm "$DIST/frames.txt"

cp web/index.html web/style.css web/app.js web/survey.json web/package.json web/results.html web/results.js "$DIST/"
mkdir -p "$DIST/api"
cp web/api/submit.js web/api/results.js "$DIST/api/"
# `vercel link` drops a token into .env.local. Never upload it.
printf '.env*\n.gitignore\n' > "$DIST/.vercelignore"
echo "Built $DIST ($(du -sh "$DIST" | cut -f1))"
