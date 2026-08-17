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
  "$ROOT/hud/init.lua"
  "$ROOT/hud/rewards.lua"
  "$ROOT/hud/hide.lua"
  "$ROOT/battle/init.lua"
  "$ROOT/battle/reactive_defense.lua"
  "$ROOT/battle/react.lua"
  "$ROOT/battle/fx.lua"
  "$ROOT/battle/dialogue.lua"
  "$ROOT/battle/strings.lua"
  "$ROOT/field/init.lua"
  "$ROOT/field/fx_catalog.lua"
  "$ROOT/field/audio.lua"
  "$ROOT/field/spectators.lua"
  "$ROOT/field/wildlife.lua"
  "$ROOT/field/callouts.lua"
  "$ROOT/field/hooks.lua"
  "$ROOT/field/hooks_draw.lua"
  "$ROOT/field/hooks_input.lua"
  "$ROOT/field/hooks_events.lua"
  "$ROOT/field/sprites.lua"
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
  hud \
  battle \
  field \
  -x "field/tests/*" \
  -x "field/tests/**" \
  -x "*.DS_Store" \
  -x "**/.DS_Store"

echo "Built $ROOT/$OUT"
unzip -l "$OUT"
