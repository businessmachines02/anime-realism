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
  "$ROOT/battle/rules/reactive_defense.lua"
  "$ROOT/battle/rules/react.lua"
  "$ROOT/battle/rules/dialogue.lua"
  "$ROOT/battle/chrome/pick.lua"
  "$ROOT/battle/chrome/bubbles.lua"
  "$ROOT/battle/fx.lua"
  "$ROOT/battle/strings.lua"
  "$ROOT/field/init.lua"
  "$ROOT/field/pad/coords.lua"
  "$ROOT/field/fx/fx_catalog.lua"
  "$ROOT/field/fx/audio.lua"
  "$ROOT/field/fx/sprites.lua"
  "$ROOT/field/session/spectators.lua"
  "$ROOT/field/session/wildlife.lua"
  "$ROOT/field/chrome/callouts.lua"
  "$ROOT/field/chrome/hooks.lua"
  "$ROOT/field/chrome/hooks_draw.lua"
  "$ROOT/field/chrome/hooks_input.lua"
  "$ROOT/field/chrome/hooks_events.lua"
  "$ROOT/field/stage/arena.lua"
  "$ROOT/field/stage/arenas/route.lua"
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
