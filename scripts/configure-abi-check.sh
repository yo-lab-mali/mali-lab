#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Must stay in step with the same fallback in build-tests.sh, which invokes this
# script without passing KDIR: if the two disagree the ABI gate checks a different
# tree than the one the tests are compiled against.
if [[ -n "${KERNEL_DIR:-}" ]]; then
  KDIR="$KERNEL_DIR"
elif [[ -d "$ROOT/work/linux/include" ]]; then
  KDIR="$ROOT/work/linux"
elif [[ -d "$ROOT/dist/headers/include" ]]; then
  KDIR="$ROOT/dist/headers"
else
  KDIR="$ROOT/work/linux"
fi
OUT="${ABI_CHECK_OUT:-$ROOT/build/abi-check}"
CC="${CC:-${CROSS_COMPILE:-}gcc}"
# -Wno-error=cpp is appended unconditionally, not merely defaulted: the probe
# puts -I$KDIR/include ahead of the UAPI directory, so <linux/types.h> resolves
# to the kernel-internal header, which deliberately emits #warning "Attempt to
# use kernel headers from user space". Keep -Werror for everything else and only
# exempt that diagnostic; otherwise the probe fails for every cross build while
# still passing for the host build, and any caller-supplied CFLAGS reintroduces it.
CFLAGS="${CFLAGS:--O2 -Wall -Wextra -Werror} -Wno-error=cpp"

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
EXPECT_IOCTL(KBASE_IOCTL_CS_QUEUE_TERMINATE,0x40088029UL);
EXPECT_IOCTL(KBASE_IOCTL_CS_QUEUE_GROUP_CREATE,0xC078803FUL);
EXPECT_IOCTL(KBASE_IOCTL_CS_QUEUE_GROUP_TERMINATE,0x4008802BUL);

EXPECT_SIZE(union kbase_ioctl_mem_alloc, 32);
EXPECT_SIZE(struct kbase_ioctl_mem_free, 8);
EXPECT_SIZE(struct kbase_ioctl_cs_queue_register, 16);
EXPECT_SIZE(union kbase_ioctl_cs_queue_bind, 16);
EXPECT_SIZE(struct kbase_ioctl_cs_queue_terminate, 8);
EXPECT_SIZE(union kbase_ioctl_cs_queue_group_create, 120);
EXPECT_SIZE(struct kbase_ioctl_cs_queue_group_term, 8);

/* The mandatory prologue: without both of these, kbase_ioctl() has no kctx and
 * returns -EPERM for every other ioctl. VERSION_CHECK also lives in the CSF
 * header (nr 52), not the core header, so it is easy to miss. */
EXPECT_IOCTL(KBASE_IOCTL_VERSION_CHECK, 0xC0048034UL);
EXPECT_IOCTL(KBASE_IOCTL_SET_FLAGS,     0x40048001UL);
EXPECT_SIZE(struct kbase_ioctl_version_check, 4);
EXPECT_SIZE(struct kbase_ioctl_set_flags, 4);

/* U/K version the tests request. CSG User-IO page allocation only happens at
 * group creation when the negotiated version is >= 1.35. */
_Static_assert(BASE_UK_VERSION_MAJOR == 1, "unexpected U/K major version");
_Static_assert(BASE_UK_VERSION_MINOR >= 35,
               "U/K minor version < 35: CSG User-IO pages are not allocated at CSG create");

/* User-IO mapping is exactly three pages; the mmap must span all of them. */
_Static_assert(BASEP_QUEUE_NR_MMAP_USER_PAGES == 3,
               "unexpected User-IO page count");

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
    echo "Expected P0 ABI (verified against AX504X08X-SW-99002-r54p0-01eac0):" >&2
    echo "  MEM_ALLOC=0xC0208005 size=32" >&2
    echo "  MEM_FREE=0x40088007 size=8" >&2
    echo "  CS_QUEUE_REGISTER=0x40108024 size=16" >&2
    echo "  CS_QUEUE_BIND=0xC0108027 size=16" >&2
    echo "  CS_QUEUE_TERMINATE=0x40088029 size=8" >&2
    echo "  CS_QUEUE_GROUP_CREATE=0xC078803F size=120" >&2
    echo "  CS_QUEUE_GROUP_TERMINATE=0x4008802B size=8" >&2
    echo "  VERSION_CHECK=0xC0048034 size=4" >&2
    echo "  SET_FLAGS=0x40048001 size=4" >&2
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
