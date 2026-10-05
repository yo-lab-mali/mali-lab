#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="${KERNEL_DIR:-$ROOT/work/linux}"
echo "Apply local patches here when the selected kernel/r54p0 source pair is known."
echo "No unverified patch is automatically applied."
