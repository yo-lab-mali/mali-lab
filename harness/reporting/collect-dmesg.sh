#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-results/reports}"
mkdir -p "$OUT"
dmesg -T > "$OUT/dmesg.txt" 2>&1 || true
