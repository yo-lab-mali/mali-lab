#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="${KERNEL_DIR:-$ROOT/work/linux}"
OUT="$ROOT/build/tests"

if [[ ! -d "$KDIR/include" ]]; then
  echo "error: kernel tree not found: $KDIR" >&2
  echo "Set KERNEL_DIR to the integrated Linux+r54p0 tree." >&2
  exit 1
fi

if [[ ! -f "$KDIR/include/uapi/gpu/arm/midgard/mali_kbase_ioctl.h" ]]; then
  echo "error: r54p0 UAPI header not found under $KDIR/include/uapi" >&2
  echo "Integrate the exact Arm r54p0 source before building tests." >&2
  exit 1
fi

mkdir -p "$OUT"
"$ROOT/scripts/configure-abi-check.sh"
CC="${CC:-${CROSS_COMPILE:-}gcc}"
CFLAGS="${CFLAGS:--O2 -g -Wall -Wextra -Wshadow -Wconversion -Wformat=2}"
CPPFLAGS="${CPPFLAGS:-} -I$ROOT/tests/common -I$KDIR/include/uapi -I$KDIR/include"
COMMON=("$ROOT/tests/common/test_common.c")

build_one() {
  local src="$1"
  local name
  name="$(basename "${src%.c}")"
  echo "[CC] $src -> $OUT/$name"
  "$CC" $CFLAGS $CPPFLAGS "${COMMON[@]}" "$src" -o "$OUT/$name"
}

# First runnable P0 set. Additional suites remain intentionally separate.
for src in \
  "$ROOT/tests/memory/001_alloc_free.c" \
  "$ROOT/tests/memory/002_alloc_mmap.c" \
  "$ROOT/tests/memory/003_mmap_unmap.c" \
  "$ROOT/tests/memory/004_free_before_unmap.c" \
  "$ROOT/tests/mmap/001_cookie_lifecycle.c" \
  "$ROOT/tests/mmap/003_vma_lifecycle.c" \
  "$ROOT/tests/user_io/001_queue_bind.c" \
  "$ROOT/tests/user_io/002_user_io_map.c"; do
  build_one "$src"
done

printf '%s\n' "P0 tests built in $OUT"
