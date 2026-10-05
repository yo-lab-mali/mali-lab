#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/results/reports/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"
uname -a > "$OUT/host-uname.txt" 2>&1 || true
echo "Artifacts collected in $OUT"
