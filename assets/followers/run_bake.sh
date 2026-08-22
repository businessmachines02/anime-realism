#!/usr/bin/env bash
# Flatten unpacked PMD Collab packs into follower_XXX.png + .kit (full rows).
#
#   ./assets/followers/run_bake.sh          # every pack under this folder
#   ./assets/followers/run_bake.sh 0005     # Charmeleon only
#
# Occupancy cap is FIT_MAX / FIT_MAX_BY_DEX at the top of bake_pmd.py.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

VENV="$HERE/.venv"
if [[ -x "$VENV/bin/python" ]]; then
  PY="$VENV/bin/python"
elif python3 -c "from PIL import Image" >/dev/null 2>&1; then
  PY="python3"
else
  echo "creating $VENV (Pillow)" >&2
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q pillow
  PY="$VENV/bin/python"
fi

exec "$PY" "$HERE/bake_pmd.py" "$@"
