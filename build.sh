#!/usr/bin/env bash
# Build an installable Gen1Recomp mod zip (package folders preserved).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MANIFEST="$ROOT/manifest.json"
MAIN="$ROOT/main.lua"

need=(
  "$MANIFEST"
  "$MAIN"
  "$ROOT/LICENSE"
  "$ROOT/lib/modload.lua"
  "$ROOT/immersion/init.lua"
  "$ROOT/immersion/rewards.lua"
  "$ROOT/battle/init.lua"
  "$ROOT/battle/reactive_defense.lua"
  "$ROOT/battle/react.lua"
  "$ROOT/field_battle/init.lua"
  "$ROOT/field_battle/fx_catalog.lua"
  "$ROOT/field_battle/audio.lua"
  "$ROOT/field_battle/spectators.lua"
  "$ROOT/field_battle/wildlife.lua"
  "$ROOT/field_battle/callouts.lua"
  "$ROOT/field_battle/hooks.lua"
  "$ROOT/field_battle/sprites.lua"
)

for f in "${need[@]}"; do
  if [[ ! -e "$f" ]]; then
    echo "error: missing $f" >&2
    exit 1
  fi
done

ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$MANIFEST")"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
OUT="${ID}-${VERSION}.zip"

rm -f "$OUT"
zip -q -r "$OUT" \
  main.lua manifest.json LICENSE \
  lib \
  immersion \
  battle \
  field_battle \
  -x "field_battle/tests/*" \
  -x "field_battle/tests/**" \
  -x "*.DS_Store" \
  -x "**/.DS_Store"

echo "Built $ROOT/$OUT"
unzip -l "$OUT"
