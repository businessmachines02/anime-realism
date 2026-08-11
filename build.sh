#!/usr/bin/env bash
# Build an installable Gen1Recomp mod zip (files at archive root).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MANIFEST="$ROOT/manifest.json"
MAIN="$ROOT/main.lua"

if [[ ! -f "$MANIFEST" || ! -f "$MAIN" ]]; then
  echo "error: manifest.json and main.lua must exist in $ROOT" >&2
  exit 1
fi

ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$MANIFEST")"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
OUT="${ID}-${VERSION}.zip"

rm -f "$OUT"
zip -j "$OUT" main.lua manifest.json

echo "Built $ROOT/$OUT"
unzip -l "$OUT"
