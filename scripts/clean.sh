#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$ROOT/build/kernel" "$ROOT/build/rootfs" "$ROOT/build/tests" \
       "$ROOT/build/tests-aarch64" "$ROOT/build/dtb" "$ROOT/build/abi-check" \
       "$ROOT/build/p0-guest-share"
