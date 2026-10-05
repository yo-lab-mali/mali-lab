#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/rootfs"
echo "Rootfs builder placeholder."
echo "Populate a minimal Linux rootfs and install tests plus mali-test utilities."
