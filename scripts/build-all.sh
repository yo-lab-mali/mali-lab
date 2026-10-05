#!/usr/bin/env bash
#
# build-all.sh - verified archive to bootable guest, in one command.
#
# This replaces the earlier chain of per-stage scripts. Two of them were
# deliberate placeholders, and a third (configure-kernel.sh) used a config order
# that cannot work: it copied the No-Mali fragment straight to .config and ran
# olddefconfig, which assigns every unlisted symbol its Kconfig default. That
# yields a near-empty kernel and drivers/gpu/arm/midgard/Kbuild aborts with
# $(error) on missing CONFIG_DMA_SHARED_BUFFER and friends.
#
# scripts/build-r54p0-kernel.sh is now the single source of truth for
# fetch/integrate/config/gate/build; the individual stage scripts delegate to it.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/scripts"

log() { printf '\n########## %s ##########\n' "$*"; }

# Fail here rather than one stage in. In a packaged lab the archive still
# verifies but there is no kernel tree to integrate it into, so without this the
# pipeline would print a green stage 1 and then stop.
KDIR="${KERNEL_DIR:-$ROOT/work/linux}"
if [[ ! -f "$KDIR/Makefile" ]]; then
  cat >&2 <<EOF
error: 'make all' cannot run: no kernel source tree at $KDIR

This is a results-only lab. The kernel tree, the unpacked DDK and the rootfs
downloads are deleted after packaging because dist/ is self-contained.

  to run the existing lab:   ./dist/run.sh
  to rebuild the P0 tests:   make tests   (uses dist/headers automatically)

Rebuilding the artifacts needs the sources back: the pinned Linux tree and the
MD5-verified DDK archive. That is the full pipeline in docs/build.md.
EOF
  exit 1
fi

log "1/5 verify the r54p0 archive"
"$S/verify-r54p0.sh"

log "2/5 kernel: fetch, integrate, config, gate, build"
"$S/build-r54p0-kernel.sh"

log "3/5 guest rootfs"
"$S/build-rootfs.sh"

log "4/5 device tree blob carrying the Mali node"
# Not optional. With CONFIG_MALI_PLATFORM_NAME="devicetree" the driver binds
# only through of_match_table, and QEMU's built-in virt DTB has no Mali node.
# Without this the module loads, appears in lsmod, emits nothing and never
# probes, so /dev/mali0 never exists and every P0 test skips.
"$ROOT/qemu/aarch64/dumpdtb.sh"

log "5/5 host P0 test binaries"
"$S/build-tests.sh"

cat <<EOF

Pipeline complete.

  Image:  $ROOT/build/kernel/Image
  Module: $ROOT/build/kernel/mali_kbase.ko
  Rootfs: $ROOT/build/rootfs/rootfs.ext4
  DTB:    $ROOT/build/dtb/virt-mali.dtb

Run the P0 suite in the guest with:

  QEMU_DTB=$ROOT/build/dtb/virt-mali.dtb $S/run-p0-qemu.sh

Confirm 'Probed as mali0' appears before trusting any skip. See docs/build.md.
EOF
