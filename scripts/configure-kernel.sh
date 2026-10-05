#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="${KERNEL_DIR:-$ROOT/work/linux}"
[[ -d "$KDIR" ]] || { echo "Missing $KDIR"; exit 1; }
cp "$ROOT/kernel/config/qemu-aarch64-r54p0.config" "$KDIR/.config"
make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}" olddefconfig
