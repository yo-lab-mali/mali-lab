#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-/tmp/mali-debugfs}"
mkdir -p "$OUT"
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug || true
find /sys/kernel/debug -maxdepth 3 -type f 2>/dev/null | sort > "$OUT/files.txt"
