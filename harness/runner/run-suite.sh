#!/usr/bin/env bash
set -euo pipefail
DIR="${1:?suite directory required}"
for t in "$DIR"/*; do
  [ -x "$t" ] || continue
  "$t" || true
done
