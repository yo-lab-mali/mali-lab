#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Default to the integrated tree, but fall back to the header kit shipped in a
# packaged lab: work/ is deleted once dist/ exists, and the tests only ever read
# the UAPI headers. Same fallback as configure-abi-check.sh, which this calls, so
# the two must agree or the ABI gate checks a different tree than the build.
if [[ -n "${KERNEL_DIR:-}" ]]; then
  KDIR="$KERNEL_DIR"
elif [[ -d "$ROOT/work/linux/include" ]]; then
  KDIR="$ROOT/work/linux"
elif [[ -d "$ROOT/dist/headers/include" ]]; then
  KDIR="$ROOT/dist/headers"
else
  KDIR="$ROOT/work/linux"
fi
# Overridable because the host runner and the QEMU runner need different
# architectures in the same tree; sharing one directory means whichever ran
# last wins and the other runner execs the wrong ELF.
OUT="${BUILD_TESTS_OUT:-$ROOT/build/tests}"

if [[ ! -d "$KDIR/include" ]]; then
  echo "error: kernel tree not found: $KDIR" >&2
  echo "Set KERNEL_DIR to the integrated Linux+r54p0 tree, or to a packaged" >&2
  echo "header kit:  KERNEL_DIR=./dist/headers make tests" >&2
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
