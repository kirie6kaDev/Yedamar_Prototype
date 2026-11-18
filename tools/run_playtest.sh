#!/usr/bin/env bash
# Headless automated playtest. Results: tests/results/<name>/playtest.{json,log}
# Usage: tools/run_playtest.sh [name] [--phases=a,b,c] [--days=N]
# Phases: profile,idle_perf,nav_static,campaign,crafting,queue_edges,actions,life,ui,save_load,walk_sample,long_run
# NOTE: wipes this project's user://saves at start (it is a test profile).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/workspace/tools/godot/Godot_v4.6.2-stable_linux.x86_64}"
NAME="${1:-latest}"; shift || true
OUT="$ROOT/tests/results/$NAME"; mkdir -p "$OUT"
[[ -d "$ROOT/.godot/imported" ]] || "$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --fixed-fps 30 --path "$ROOT" -s res://tests/playtest.gd -- --out="$OUT" "$@" 2>&1 | tee "$OUT/stdout.txt"
