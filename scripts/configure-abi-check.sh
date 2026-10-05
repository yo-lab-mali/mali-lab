#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="${KERNEL_DIR:-$ROOT/work/linux}"
OUT="${ABI_CHECK_OUT:-$ROOT/build/abi-check}"
CC="${CC:-${CROSS_COMPILE:-}gcc}"
CFLAGS="${CFLAGS:--O2 -Wall -Wextra -Werror}"

BASE="$KDIR/include/uapi/gpu/arm/midgard"
CORE="$BASE/mali_kbase_ioctl.h"
BASE_COMMON="$BASE/mali_base_common_kernel.h"
CSF="$BASE/csf/mali_kbase_csf_ioctl.h"

fail() { echo "error: r54p0 ABI check: $*" >&2; exit 1; }

[[ -d "$KDIR/include" ]] || fail "kernel tree not found: $KDIR (set KERNEL_DIR)"
[[ -f "$CORE" ]] || fail "missing $CORE; integrate the exact Arm r54p0 source/UAPI first"
[[ -f "$BASE_COMMON" ]] || fail "missing $BASE_COMMON; integrated UAPI is incomplete"
[[ -f "$CSF" ]] || fail "missing $CSF; CSF UAPI is required by the User-IO P0 tests"
command -v "$CC" >/dev/null 2>&1 || fail "compiler not found: $CC"

mkdir -p "$OUT"
SRC="$OUT/probe.c"
OBJ="$OUT/probe.o"
cat > "$SRC" <<'PROBE'
#include <stdint.h>
#include <stddef.h>
#include <linux/ioctl.h>
#include "mali_uapi.h"

#define EXPECT_IOCTL(name, value) \
    _Static_assert((name) == (value), #name " has unexpected ioctl encoding")
#define EXPECT_SIZE(type, value) \
    _Static_assert(sizeof(type) == (value), "sizeof(" #type ") is not " #value)

/* r54p0 P0 ABI contract: ioctl command numbers and encoded directions/sizes. */
EXPECT_IOCTL(KBASE_IOCTL_MEM_ALLOC, 0xC0208005UL);
EXPECT_IOCTL(KBASE_IOCTL_MEM_FREE,  0x40088007UL);
EXPECT_IOCTL(KBASE_IOCTL_CS_QUEUE_REGISTER, 0x40108024UL);
EXPECT_IOCTL(KBASE_IOCTL_CS_QUEUE_BIND,     0xC0108027UL);
EXPECT_IOCTL(KBASE_IOCTL_CS_QUEUE_TERMINATE,0x40108029UL);
EXPECT_IOCTL(KBASE_IOCTL_CS_QUEUE_GROUP_CREATE,0xC058803AUL);
EXPECT_IOCTL(KBASE_IOCTL_CS_QUEUE_GROUP_TERMINATE,0x4008802BUL);

EXPECT_SIZE(union kbase_ioctl_mem_alloc, 32);
EXPECT_SIZE(struct kbase_ioctl_mem_free, 8);
EXPECT_SIZE(struct kbase_ioctl_cs_queue_register, 16);
EXPECT_SIZE(union kbase_ioctl_cs_queue_bind, 16);
EXPECT_SIZE(struct kbase_ioctl_cs_queue_terminate, 8);
EXPECT_SIZE(union kbase_ioctl_cs_queue_group_create, 112);
EXPECT_SIZE(struct kbase_ioctl_cs_queue_group_term, 8);

int main(void) { return 0; }
PROBE

# Keep the probe include path identical to the test build and intentionally use
# the kernel's UAPI tree rather than a copied compatibility header.
if ! "$CC" $CFLAGS -I"$ROOT/tests/common" -I"$KDIR/include/uapi" -I"$KDIR/include" -c "$SRC" -o "$OBJ" 2>"$OUT/error.log"; then
    echo "error: r54p0 ABI check failed against the integrated UAPI." >&2
    echo "  kernel tree: $KDIR" >&2
    echo "  core UAPI:   $CORE" >&2
    echo "  CSF UAPI:    $CSF" >&2
    echo "" >&2
    cat "$OUT/error.log" >&2
    echo "" >&2
    echo "Expected P0 ABI:" >&2
    echo "  MEM_ALLOC=0xC0208005 size=32" >&2
    echo "  MEM_FREE=0x40088007 size=8" >&2
    echo "  CS_QUEUE_REGISTER=0x40108024 size=16" >&2
    echo "  CS_QUEUE_BIND=0xC0108027 size=16" >&2
    echo "  CS_QUEUE_TERMINATE=0x40108029 size=8" >&2
    echo "  CS_QUEUE_GROUP_CREATE=0xC058803A size=112" >&2
    echo "  CS_QUEUE_GROUP_TERMINATE=0x4008802B size=8" >&2
    exit 1
fi

cat > "$OUT/manifest.txt" <<EOF_MANIFEST
status=ok
kernel_dir=$KDIR
core_header=$CORE
csf_header=$CSF
compiler=$CC
EOF_MANIFEST

echo "[ABI] r54p0 UAPI detected and P0 ioctl/size contract verified"
echo "[ABI] headers: $CORE ; $CSF"
echo "[ABI] probe: $OBJ"
