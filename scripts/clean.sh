#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$ROOT/build/kernel" "$ROOT/build/rootfs" "$ROOT/build/tests" "$ROOT/build/dtb"
