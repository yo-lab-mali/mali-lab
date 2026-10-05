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
#   Image.gz, rootfs.ext4.gz, mali_kbase.ko.gz
#                        the bootable pair + module, gzipped because the repo
#                        host limits files to 100 MB and rootfs is 512 MB raw;
#                        run.sh decompresses them on first boot
#   virt-mali.dtb        REQUIRED for the driver to probe. QEMU synthesises its
#                        own virt DTB when -dtb is omitted and it has no Mali node
#   bin/                 the 8 prebuilt aarch64 P0 binaries; there are no
#                        sources in a packaged lab, so they cannot be rebuilt
#   run.sh, qemu.env     standalone entry point and its machine settings
#   manifest.txt, SHA256SUMS  versions and a sha256 for every file above
#
# Usage:
#   ./scripts/package-dist.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${DIST:-$ROOT/dist}"
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
rm -rf "$DIST"
mkdir -p "$DIST/bin"

# rootfs.ext4 is 512 MB raw and the repo host limits files to 100 MB, so the
# shipped artifacts are the gzipped forms; run.sh decompresses them on first
# boot. -9 because these are the only artifacts that travel with git clones.
gzip -9 -c "$KERNEL"  > "$DIST/Image.gz"
gzip -9 -c "$ROOTFS"  > "$DIST/rootfs.ext4.gz"
gzip -9 -c "$KO"      > "$DIST/mali_kbase.ko.gz"
cp "$DTB"  "$DIST/virt-mali.dtb"
cp "$DTS"  "$DIST/virt-mali.dts"

for t in "${TESTS[@]}"; do
  install -m 0755 "$TESTBIN/$t" "$DIST/bin/$t"
done

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
  echo "# artifacts are gzipped; run.sh decompresses them on first boot"
  echo "# integrity: sha256sum -c SHA256SUMS"
  echo
  echo "[build]"
  if [[ -f "$KERNEL_MANIFEST" ]]; then
    sed 's/^/  /' "$KERNEL_MANIFEST"
  fi
  echo "  config_fragment=$ROOT/kernel/config/qemu-aarch64-r54p0.config"
  echo "  host=$(uname -s) $(uname -r) $(uname -m)"
} > "$DIST/manifest.txt"

(
  cd "$DIST"
  # Sorted, and excluding SHA256SUMS itself so the file can verify in place.
  find . -type f ! -name SHA256SUMS ! -name manifest.txt ! -path './.run/*' ! -path './.cache/*' -print0 \
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

  after this, work/, build/, downloads/ and dist/headers/ can be deleted:
    nothing in dist/ is needed at run time except what run.sh decompresses.
EOF