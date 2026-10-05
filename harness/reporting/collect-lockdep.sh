#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-results/reports}"
mkdir -p "$OUT"
echo "collector placeholder" > "$OUT/README.txt"
