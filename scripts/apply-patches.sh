#!/usr/bin/env bash
#
# apply-patches.sh - report the patch state for the selected target.
#
# Deliberately applies nothing. The reason is recorded, not guessed:
#
#   aarch64 (the supported route)
#     No local patch is needed. The pinned pairing Linux 6.6.158 + r54p0 builds
#     and boots unmodified, with the No-Mali driver as a loadable module. The
#     device tree node lives in qemu/aarch64/dt/mali-no-mali.dtsi, applied by
#     qemu/aarch64/dumpdtb.sh, not by patching the kernel.
#
#   x86
#     Not functional. Arm ships six patches in patches_for_virtual_device.zip
#     targeting r54p0; kernel/patches/x86/ holds five stubs with numbering that
#     does not match Arm's (see kernel/patches/README.md for the mapping). The
#     real patches have to be vendored and verified against the selected
#     kernel/r54p0 pair first. See docs/qemu-x86_64.md.
#
set -euo pipefail
ARCH="${ARCH:-arm64}"

case "$ARCH" in
  arm64)
    echo "apply-patches.sh: aarch64 needs no patches; nothing to do."
    echo "  The Mali node is supplied by qemu/aarch64/dt/mali-no-mali.dtsi via"
    echo "  'make dtb'. See kernel/patches/README.md and docs/qemu-x86_64.md."
    ;;
  *)
    echo "apply-patches.sh: $ARCH route is not vendored; nothing applied." >&2
    echo "  kernel/patches/x86/ contains stubs only. See kernel/patches/README.md" >&2
    ;;
esac
