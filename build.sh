#!/usr/bin/env bash
# Build an installable Gen1Recomp mod zip (paths preserved for packages).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MANIFEST="$ROOT/manifest.json"
MAIN="$ROOT/main.lua"

need=(
  "$MANIFEST"
  "$MAIN"
  "$ROOT/lib/modload.lua"
  "$ROOT/immersion/init.lua"
  "$ROOT/battle/init.lua"
  "$ROOT/battle/reactive_defense.lua"
  "$ROOT/field_battle/init.lua"
  "$ROOT/field_battle/layout.lua"
  "$ROOT/field_battle/sprites.lua"
  "$ROOT/field_battle/lifecycle.lua"
  "$ROOT/field_battle/coords.lua"
  "$ROOT/field_battle/themes.lua"
  "$ROOT/field_battle/grid.lua"
  "$ROOT/field_battle/cast.lua"
  "$ROOT/field_battle/cues.lua"
  "$ROOT/field_battle/projectiles.lua"
  "$ROOT/field_battle/anims.lua"
  "$ROOT/field_battle/compat.lua"
  "$ROOT/field_battle/arena.lua"
  "$ROOT/field_battle/survey.lua"
  "$ROOT/field_battle/debug.lua"
  "$ROOT/field_battle/ui.lua"
  "$ROOT/field_battle/hooks.lua"
  "$ROOT/field_battle/intercept.lua"
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
zip -q "$OUT" \
  main.lua manifest.json \
  lib/modload.lua \
  immersion/init.lua \
  battle/init.lua \
  battle/reactive_defense.lua \
  field_battle/init.lua \
  field_battle/layout.lua \
  field_battle/sprites.lua \
  field_battle/lifecycle.lua \
  field_battle/coords.lua \
  field_battle/themes.lua \
  field_battle/grid.lua \
  field_battle/cast.lua \
  field_battle/cues.lua \
  field_battle/projectiles.lua \
  field_battle/anims.lua \
  field_battle/compat.lua \
  field_battle/arena.lua \
  field_battle/survey.lua \
  field_battle/debug.lua \
  field_battle/ui.lua \
  field_battle/hooks.lua \
  field_battle/intercept.lua \
  field_battle/SPEC.md

echo "Built $ROOT/$OUT"
unzip -l "$OUT"
