#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/configs/qemu-aarch64.env"
KERNEL="$ROOT/build/kernel/Image"
ROOTFS="$ROOT/build/rootfs/rootfs.ext4"
[[ -f "$KERNEL" ]] || { echo "Missing $KERNEL"; exit 1; }
[[ -f "$ROOTFS" ]] || { echo "Missing $ROOTFS"; exit 1; }
exec "$QEMU" -machine "$MACHINE" -cpu "$CPU" -m "$MEMORY" -smp "$SMP"   -nographic -kernel "$KERNEL"   -append "console=ttyAMA0 root=/dev/vda rw"   -drive "if=virtio,format=raw,file=$ROOTFS"
