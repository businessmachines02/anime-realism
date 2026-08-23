#!/usr/bin/env bash
# Build an installable Gen1Recomp mod zip (package folders preserved).
#
# One pass through Python's zipfile. Incremental `zip a.zip file` updates
# plus PMD flip names (`Happy^.png`) make love.filesystem.mount fail
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

python3 - <<'PY' "$OUT"
import sys
import zipfile
from pathlib import Path

out = Path(sys.argv[1])
files = []


def add_file(path):
    p = Path(path)
    if not p.is_file():
        return
    name = p.as_posix()
    if "^" in name or name.endswith(".DS_Store"):
        return
    files.append(p)


def add_tree(root, skip_parts=()):
    root = Path(root)
    if not root.is_dir():
        return
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if any(part in skip_parts for part in p.parts):
            continue
        add_file(p)


add_file("main.lua")
add_file("manifest.json")
add_file("LICENSE")
add_tree("lib")
add_tree("hud")
add_tree("battle")
add_tree("field", skip_parts=("tests",))
add_file("assets/follower-kit.md")
add_file("assets/followers/bake_pmd.py")
add_tree("assets/followers/pmd")
for p in sorted(Path("assets/followers").glob("follower_*.png")):
    add_file(p)
for p in sorted(Path("assets/followers").glob("follower_*.kit")):
    add_file(p)

portrait = Path("assets/portrait")
if portrait.is_dir():
    for i in range(1, 152):
        folder = portrait / f"{i:04d}"
        if not folder.is_dir():
            continue
        for p in sorted(folder.iterdir()):
            if p.is_file() and (p.suffix == ".png" or p.name == "credits.txt"):
                add_file(p)

seen = set()
ordered = []
for p in files:
    key = p.as_posix()
    if key in seen:
        continue
    seen.add(key)
    ordered.append(p)

with zipfile.ZipFile(
    out, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=False
) as zf:
    for p in ordered:
        zf.write(p, p.as_posix())

print(f"packed {len(ordered)} files")
PY

echo "Built $ROOT/$OUT"
python3 - <<'PY' "$OUT"
import sys, zipfile
from pathlib import Path
p = Path(sys.argv[1])
with zipfile.ZipFile(p) as zf:
    names = zf.namelist()
faces = [n for n in names if n.startswith("assets/portrait/") and n.endswith(".png")]
carets = [n for n in names if "^" in n]
print(f"  {p.stat().st_size} bytes, {len(names)} entries, {len(faces)} portraits")
if carets:
    raise SystemExit(f"error: zip contains {len(carets)} '^' names (PhysicsFS cannot mount)")
if "manifest.json" not in names or "main.lua" not in names:
    raise SystemExit("error: zip missing manifest.json or main.lua at root")
PY
