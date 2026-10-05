#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="${KERNEL_DIR:-$ROOT/work/linux}"
mkdir -p "$ROOT/build/kernel"
make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}" -j"${JOBS:-$(nproc)}" Image modules dtbs
cp "$KDIR/arch/arm64/boot/Image" "$ROOT/build/kernel/Image"
