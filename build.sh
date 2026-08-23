#!/usr/bin/env bash
# Build an installable Gen1Recomp mod zip (package folders preserved).
#
# Info-ZIP, a handful of updates, same shape as the zips the launcher already
# mounts. Python zipfile (v4.2.2) and 2k incremental `zip file.zip a` updates
# plus `Emotion^.png` names all fail love.filesystem.mount
# ("that .zip could not be opened").
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
  "$ROOT/battle/rules/emotions.lua"
  "$ROOT/battle/chrome/pick.lua"
  "$ROOT/battle/chrome/bubbles.lua"
  "$ROOT/battle/chrome/portraits.lua"
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

# Directory entries included (zip -r), extras stripped (-X). One pass per
# tree — not one zip-update per portrait.
zip -q -X -r "$OUT" \
  main.lua manifest.json LICENSE \
  lib \
  hud \
  battle \
  field \
  -x "field/tests/*" \
  -x "field/tests/*/*" \
  -x "field/tests/*/*/*" \
  -x "field/tests/*/*/*/*" \
  -x "field/lab/*" \
  -x "field/lab/*/*" \
  -x "*.DS_Store" \
  -x "*/*.DS_Store"

if [[ -f "$ROOT/assets/follower-kit.md" ]]; then
  zip -q -X "$OUT" assets/follower-kit.md
fi
if [[ -d "$ROOT/assets/followers/pmd" ]]; then
  zip -q -X -r "$OUT" assets/followers/pmd \
    -x "*.DS_Store"
fi

shopt -s nullglob
kits=(assets/followers/follower_*.png assets/followers/follower_*.kit)
if ((${#kits[@]} > 0)); then
  zip -q -X "$OUT" "${kits[@]}"
fi

# Faces the mood table actually loads. Flip frames (`^.png`) and unused
# PMD moods stay out of the archive.
FACE_LIST="$(mktemp)"
python3 - <<'PY' > "$FACE_LIST"
from pathlib import Path
emotions = (
    "Normal", "Pain", "Determined", "Worried",
    "Angry", "Stunned", "Surprised", "Sigh",
)
root = Path("assets/portrait")
for i in range(1, 152):
    folder = root / f"{i:04d}"
    if not folder.is_dir():
        continue
    credits = folder / "credits.txt"
    if credits.is_file():
        print(credits.as_posix())
    for name in emotions:
        png = folder / f"{name}.png"
        if png.is_file():
            print(png.as_posix())
PY
if [[ -s "$FACE_LIST" ]]; then
  zip -q -X -@ "$OUT" < "$FACE_LIST"
fi
rm -f "$FACE_LIST"

echo "Built $ROOT/$OUT"
python3 - <<'PY' "$OUT"
import sys, zipfile
from pathlib import Path
p = Path(sys.argv[1])
with zipfile.ZipFile(p) as zf:
    names = zf.namelist()
faces = [n for n in names if n.startswith("assets/portrait/") and n.endswith(".png")]
carets = [n for n in names if "^" in n]
tests = [n for n in names if n.startswith("field/tests/")]
labs = [n for n in names if n.startswith("field/lab/")]
print(f"  {p.stat().st_size} bytes, {len(names)} entries, {len(faces)} portraits")
if carets:
    raise SystemExit(f"error: zip contains {len(carets)} '^' names")
if tests:
    raise SystemExit("error: field tests included in zip")
if labs:
    raise SystemExit("error: field lab included in zip")
if "manifest.json" not in names or "main.lua" not in names:
    raise SystemExit("error: zip missing manifest.json or main.lua at root")
if "lib/" not in names and not any(n.startswith("lib/") for n in names):
    raise SystemExit("error: zip missing lib/")
PY
