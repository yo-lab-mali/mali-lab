#!/usr/bin/env bash
#
# run.sh - boot the built guest on QEMU virt (arm64).
#
# The -dtb argument is not decoration. With CONFIG_MALI_PLATFORM_NAME="devicetree"
# Kbase binds only through of_match_table (kbase_dt_ids[] in
# mali_kbase_core_linux.c), and QEMU synthesises its own virt DTB when -dtb is
# omitted -- one with no Mali node. The module then loads, shows up in lsmod,
# prints nothing and never probes: no /dev/mali0, and every P0 test silently
# skips. "Probed as mali0" in the boot log is the only reliable signal that the
# driver actually initialised. See docs/qemu-aarch64.md.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/configs/qemu-aarch64.env"

KERNEL="$ROOT/build/kernel/Image"
ROOTFS="$ROOT/build/rootfs/rootfs.ext4"
[[ -f "$KERNEL" ]] || { echo "Missing $KERNEL (run: make kernel)"; exit 1; }
[[ -f "$ROOTFS" ]] || { echo "Missing $ROOTFS (run: make rootfs)"; exit 1; }

DTB="${QEMU_DTB:-$ROOT/build/dtb/virt-mali.dtb}"
dtb_arg=()
if [[ -f "$DTB" ]]; then
  dtb_arg=(-dtb "$DTB")
  echo "using DTB $DTB"
else
  echo "warning: no DTB at $DTB" >&2
  echo "warning: run 'make dtb'; without a Mali node the driver never probes" >&2
  echo "warning: and /dev/mali0 will not exist, so every test will skip" >&2
fi

# This is the interactive boot: no init= on the cmdline, so the guest drops to a
# busybox shell with no driver loaded. The automated suite is a different cmdline
# (init=/usr/local/bin/mali-p0-guest) driven by scripts/run-p0-qemu.sh.
cat >&2 <<EOF
booting $KERNEL interactively; guest drops to a busybox shell with no module loaded.
at the shell:
    mount -t proc     proc /proc
    mount -t sysfs    sys  /sys
    mount -t devtmpfs dev  /dev
    insmod /lib/modules/mali_kbase.ko
    dmesg | grep -i mali        # 'Probed as mali0' is the success signal
or run the suite unattended with 'make test-p0-qemu'.
EOF

# "$@" is forwarded: qemu/aarch64/run-debug.sh relies on it to pass -s -S and
# boot paused for a debugger.
exec "$QEMU" \
  -machine "$MACHINE" -cpu "$CPU" -m "$MEMORY" -smp "$SMP" \
  -nographic \
  -kernel "$KERNEL" \
  ${dtb_arg[@]+"${dtb_arg[@]}"} \
  -append "console=ttyAMA0 root=/dev/vda rw" \
  -drive "if=virtio,format=raw,file=$ROOTFS" \
  "$@"
