#!/usr/bin/env bash
# Open the field lab window (Love 11). Does not launch Gen1Recomp.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! command -v love >/dev/null 2>&1; then
  echo "error: love (11.x) is not on PATH" >&2
  echo "  brew install love   # or https://love2d.org" >&2
  exit 1
fi
exec love "$HERE" "$@"