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
  "$ROOT/lib/log.lua"
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

if [[ -f "$ROOT/assets/follower-kit.md" ]]; then
  zip -q "$OUT" assets/follower-kit.md
fi
if [[ -f "$ROOT/assets/followers/bake_pmd.py" ]]; then
  zip -q "$OUT" assets/followers/bake_pmd.py
fi
if [[ -d "$ROOT/assets/followers/pmd" ]]; then
  zip -q -r "$OUT" assets/followers/pmd \
    -x "**/.DS_Store"
fi
# Baked 4×24 kits only — never pack PMD source folders (0001/…).
while IFS= read -r kit; do
  zip -q "$OUT" "$kit"
done < <(find assets/followers -maxdepth 1 -name 'follower_*.png' | sort)

echo "Built $ROOT/$OUT"
unzip -l "$OUT"
