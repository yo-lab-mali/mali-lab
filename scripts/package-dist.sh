#!/usr/bin/env bash
#
# package-dist.sh - assemble the portable, results-only lab in dist/.
#
# Collects the outputs of the kernel build, rootfs build, DTB splice and test
# build into one folder that boots and runs the P0 suite with nothing but
# qemu-system-aarch64 on the host. After this, work/ and the rootfs staging tree
# can be deleted: nothing in dist/ is derived from them at run time.
#
# What goes in, and why each piece is needed:
#   Image, rootfs.ext4   the bootable pair
#   mali_kbase.ko        the module, also embedded in rootfs at /lib/modules/;
#                        kept standalone so the image can be rebuilt if needed
#   virt-mali.dtb        REQUIRED for the driver to probe. QEMU synthesises its
#                        own virt DTB when -dtb is omitted and it has no Mali node
#   bin/                 the 8 prebuilt aarch64 P0 binaries; there are no
#                        sources in a packaged lab, so they cannot be rebuilt
#   headers/             include/uapi + include/linux from the integrated tree,
#                        so 'make tests' and the ABI gate still work offline
#   run.sh, qemu.env     standalone entry point and its machine settings
#   manifest.txt         versions and a sha256 for every file above
#
# Usage:
#   ./scripts/package-dist.sh
#   KERNEL_DIR=/path/to/integrated/tree ./scripts/package-dist.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${DIST:-$ROOT/dist}"
# Same fallback as build-tests.sh and configure-abi-check.sh: work/ is deleted
# once a lab is packaged, and the header kit in the existing dist/ is the only
# UAPI source left. Without this, re-packaging a results-only checkout fails.
if [[ -n "${KERNEL_DIR:-}" ]]; then
  KDIR="$KERNEL_DIR"
elif [[ -d "$ROOT/work/linux/include" ]]; then
  KDIR="$ROOT/work/linux"
elif [[ -d "$ROOT/dist/headers/include" ]]; then
  KDIR="$ROOT/dist/headers"
else
  KDIR="$ROOT/work/linux"
fi
BUILD="${BUILD:-$ROOT/build}"

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '  %s\n' "$*"; }

# The P0 binaries, named exactly as rootfs/overlay/usr/local/bin/mali-p0-guest
# execs them. A rename here silently becomes a missing binary in the guest.
TESTS=(
  001_alloc_free 002_alloc_mmap 003_mmap_unmap 004_free_before_unmap
  001_cookie_lifecycle 003_vma_lifecycle
  001_queue_bind 002_user_io_map
)

KERNEL="$BUILD/kernel/Image"
KO="$BUILD/kernel/mali_kbase.ko"
KERNEL_MANIFEST="$BUILD/kernel/manifest.txt"
ROOTFS="$BUILD/rootfs/rootfs.ext4"
DTB="$BUILD/dtb/virt-mali.dtb"
DTS="$BUILD/dtb/virt-mali.dts"
TESTBIN="$BUILD/tests-aarch64"

# ---- preflight: every input must already exist -----------------------------
missing=()
[[ -f "$KERNEL" ]]        || missing+=("$KERNEL (run: make kernel)")
[[ -f "$KO" ]]            || missing+=("$KO (run: make kernel)")
[[ -f "$ROOTFS" ]]        || missing+=("$ROOTFS (run: make rootfs)")
[[ -f "$DTB" ]]           || missing+=("$DTB (run: make dtb)")
[[ -f "$DTS" ]]           || missing+=("$DTS (run: make dtb)")
[[ -f "$KERNEL_MANIFEST" ]] || missing+=("$KERNEL_MANIFEST (run: make kernel)")
[[ -d "$TESTBIN" ]]       || missing+=("$TESTBIN (run: make tests with CROSS_COMPILE=aarch64-linux-gnu-)")
for t in "${TESTS[@]}"; do
  [[ -f "$TESTBIN/$t" ]] || missing+=("$TESTBIN/$t (run: make tests)")
done
[[ -d "$KDIR/include/uapi/gpu/arm/midgard" ]] || \
  missing+=("$KDIR/include/uapi/gpu/arm/midgard (integrated kernel tree; see docs/build.md)")
if (( ${#missing[@]} )); then
  printf 'error: cannot package, %d input(s) missing:\n' "${#missing[@]}" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

# The DTB must actually carry the Mali node, or the packaged lab boots a guest
# whose driver never probes and every test skips.
if command -v dtc >/dev/null 2>&1; then
  if ! dtc -I dtb -O dts "$DTB" 2>/dev/null | grep -q 'arm,mali-midgard'; then
    die "$DTB has no arm,mali-midgard node; the packaged lab would never probe"
  fi
else
  info "warning: dtc not installed, skipping the Mali-node check on $DTB" >&2
fi

# ---- assemble ---------------------------------------------------------------
# dist/ is fully regenerated. run.sh is generated from scripts/dist-run.sh rather
# than tracked in place, so wiping dist/ can never destroy a tracked file.
#
# The header source is staged out first: in a results-only checkout the fallback
# above resolves KDIR to the *existing* dist/headers, which the wipe below would
# otherwise delete a few lines before it is copied from.
HEADER_SRC="$KDIR"
STAGED_HDR=""
if [[ "$(cd "$KDIR" && pwd -P)" == "$(cd "$DIST" 2>/dev/null && pwd -P || echo x)"/* ]]; then
  STAGED_HDR="$(mktemp -d)"
  trap 'rm -rf "$STAGED_HDR"' EXIT
  info "staging header kit out of $DIST before regenerating it"
  cp -a "$KDIR/include" "$STAGED_HDR/include"
  HEADER_SRC="$STAGED_HDR"
fi

rm -rf "$DIST"
mkdir -p "$DIST/bin" "$DIST/headers/include"

# --sparse=always: rootfs.ext4 is 512 MB apparent but ~102 MB of real blocks.
# A plain cp would expand the holes and triple the size of the package.
cp --sparse=always "$KERNEL" "$DIST/Image"
cp --sparse=always "$ROOTFS" "$DIST/rootfs.ext4"
cp "$KO"   "$DIST/mali_kbase.ko"
cp "$DTB"  "$DIST/virt-mali.dtb"
cp "$DTS"  "$DIST/virt-mali.dts"

for t in "${TESTS[@]}"; do
  install -m 0755 "$TESTBIN/$t" "$DIST/bin/$t"
done

info "copying UAPI kit (include/uapi + include/linux) for offline test rebuilds"
# include/linux cannot be dropped: include/uapi/linux/stddef.h includes
# <linux/compiler_types.h>, which lives only in include/linux. Verified by
# compiling the P0 tests for both aarch64 and the host against this subset alone.
cp -a "$HEADER_SRC/include/uapi" "$HEADER_SRC/include/linux" "$DIST/headers/include/"

install -m 0755 "$ROOT/scripts/dist-run.sh" "$DIST/run.sh"
cp "$ROOT/configs/qemu-aarch64.env" "$DIST/qemu.env"

# ---- manifest ---------------------------------------------------------------
# Two files, deliberately. manifest.txt is prose for a human: what produced this
# and on what. SHA256SUMS is in the format sha256sum -c expects. Folding the
# checksums into the prose file means every section header and key=value line has
# to be filtered out before verification, which is exactly the kind of fiddly
# step that gets skipped and then the checksums are never checked.
{
  echo "# mali-lab portable lab manifest"
  echo "# generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# integrity: sha256sum -c SHA256SUMS"
  echo
  echo "[build]"
  if [[ -f "$KERNEL_MANIFEST" ]]; then
    sed 's/^/  /' "$KERNEL_MANIFEST"
  fi
  echo "  config_fragment=$ROOT/kernel/config/qemu-aarch64-r54p0.config"
  echo "  uapi_source=$KDIR/include/uapi/gpu/arm/midgard"
  echo "  host=$(uname -s) $(uname -r) $(uname -m)"
} > "$DIST/manifest.txt"

(
  cd "$DIST"
  # Sorted, and excluding SHA256SUMS itself so the file can verify in place.
  find . -type f ! -name SHA256SUMS ! -name manifest.txt ! -path './.run/*' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum > SHA256SUMS
)

size="$(du -sh "$DIST" | cut -f1)"
files="$(find "$DIST" -type f | wc -l)"

cat <<EOF

Portable lab packaged: $DIST
  $files files, $size total

  run it with:   $DIST/run.sh
  verify it with: cd $DIST && sha256sum -c SHA256SUMS
  provenance:     $DIST/manifest.txt

  after this, work/ and build/rootfs/stage/ can be deleted:
    nothing in dist/ is derived from them at run time.
  KERNEL_DIR=$DIST/headers keeps 'make tests' and the ABI gate working offline.
EOF