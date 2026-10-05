#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/configs/lab.env.example" 2>/dev/null || true
KDIR="${KERNEL_DIR:-$ROOT/work/linux}"
MALI_ARCHIVE="${MALI_ARCHIVE:-$ROOT/downloads/r54p0-01eac0.tar.gz}"
[[ -d "$KDIR" ]] || { echo "Kernel tree missing: $KDIR"; exit 1; }
[[ -f "$MALI_ARCHIVE" ]] || { echo "Mali archive missing: $MALI_ARCHIVE"; exit 1; }
echo "Integration placeholder: unpack the verified Arm archive and integrate its"
echo "driver/product/kernel tree into $KDIR/drivers/gpu/arm/midgard."
echo "Apply the exact integration procedure documented for your selected kernel."
