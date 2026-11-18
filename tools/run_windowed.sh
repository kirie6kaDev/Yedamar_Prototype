#!/usr/bin/env bash
# Launch Noctis Live windowed on the current X display (box desktop: DISPLAY=:3).
# Usage: tools/run_windowed.sh [--fresh] [extra godot args...]
#   --fresh  delete this project's user:// saves first (otherwise the "realtime" slot is auto-loaded)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/workspace/tools/godot/Godot_v4.6.2-stable_linux.x86_64}"
export DISPLAY="${DISPLAY:-:3}"
if [[ "${1:-}" == "--fresh" ]]; then
  shift
  rm -f "$HOME/.local/share/godot/app_userdata/Йедамар — Дорога через Лиору/saves/"*
fi
if [[ ! -d "$ROOT/.godot/imported" ]]; then
  echo "First run: importing assets (about 1 minute)..."
  "$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
fi
exec "$GODOT" --path "$ROOT" "$@"
