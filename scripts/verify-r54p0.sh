#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/configs/r54p0.env"
ARCHIVE="${1:-$ROOT/downloads/${MALI_RELEASE}.tar.gz}"
EXPECTED="$MALI_MD5"
[[ -f "$ARCHIVE" ]] || { echo "Missing archive: $ARCHIVE"; exit 1; }
ACTUAL="$(md5sum "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "MD5 mismatch: expected $EXPECTED got $ACTUAL"; exit 1; }
echo "Verified $MALI_RELEASE"
