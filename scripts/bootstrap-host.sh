#!/usr/bin/env bash
set -euo pipefail
command -v git >/dev/null || echo "missing: git"
command -v make >/dev/null || echo "missing: make"
command -v qemu-system-aarch64 >/dev/null || echo "missing: qemu-system-aarch64"
command -v aarch64-linux-gnu-gcc >/dev/null || echo "missing: aarch64-linux-gnu-gcc"
echo "Bootstrap check complete."
