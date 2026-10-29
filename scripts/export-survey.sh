#!/bin/bash
# Downloads every survey response from the walkthrough's private Blob store
# and writes them to CSV files on local disk, outside iCloud:
#   ~/Library/Developer/Background AI Coach/survey-export
# responses-responses.csv has one row per tester; responses-picks.csv has one
# row per card pick. Pass tests/ to export the test submissions instead.
# Needs the Vercel login and the linked web-dist folder that build-web.sh makes.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

OUT="${RECOMMENDER_BUILD_DIR:-$HOME/Library/Developer/Background AI Coach}"
EXPORT="$OUT/survey-export"
PREFIX="${1:-responses/}"
NAME="${PREFIX%/}"
RAW="$EXPORT/raw/$NAME"
mkdir -p "$RAW"
chmod 700 "$EXPORT"

cd "$OUT/web-dist"
# The store's read-write token lives in a private file here, never in the site folder.
[ -f "$EXPORT/.env.production" ] || npx --yes vercel env pull "$EXPORT/.env.production" --environment=production --yes >/dev/null
chmod 600 "$EXPORT/.env.production"
TOKEN="$(grep '^BLOB_READ_WRITE_TOKEN=' "$EXPORT/.env.production" | cut -d= -f2- | tr -d '"')"
blob() { env -u VERCEL_OIDC_TOKEN npx --yes vercel blob "$@" --rw-token "$TOKEN"; }

blob list --json --prefix "$PREFIX" --limit 1000 > "$EXPORT/list.json"
python3 -I -c 'import json, sys; [print(b["pathname"]) for b in json.load(open(sys.argv[1]))["blobs"]]' "$EXPORT/list.json" |
  while read -r path; do
    file="$RAW/$(basename "$path")"
    [ -f "$file" ] || blob get "$path" --access private --output "$file" >/dev/null
  done

python3 -I "$REPO/web/export_responses.py" "$RAW" "$REPO/web/survey.json" "$EXPORT" "$NAME"
