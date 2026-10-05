#!/bin/bash
#
# manual-test.sh - Interactive manual testing for the P0 suite VM.
#
# Boot the prebuilt dist/ VM into a shell so you can inspect the driver, run
# tests one at a time, examine dmesg, etc. This is a real interactive console,
# not the automated guest runner.
#
# Usage:
#   ./scripts/manual-test.sh          boot to an interactive shell
#   ./scripts/manual-test.sh -s       same, but also start sshd (if built in)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"

# shellcheck disable=SC1091
source "$ROOT/configs/qemu-aarch64.env"

CACHE="$DIST/.cache"
RUN="$DIST/.run"
mkdir -p "$CACHE" "$RUN"

echo "Decompressing artifacts into $CACHE (if needed)..." >&2
for name in Image rootfs.ext4; do
    gz="$DIST/$name.gz"
    dst="$CACHE/$name"
    [[ -f "$gz" ]] || { echo "missing $gz" >&2; exit 1; }
    if [[ ! -f "$dst" || "$gz" -nt "$dst" ]]; then
        gzip -dc "$gz" > "$dst.tmp" && mv "$dst.tmp" "$dst"
    fi
done

echo "Booting interactive QEMU guest..." >&2
echo "Once at the guest shell, to load the driver:" >&2
echo "  mount -t proc proc /proc" >&2
echo "  mount -t sysfs sys /sys" >&2
echo "  mount -t devtmpfs dev /dev" >&2
echo "  insmod /lib/modules/mali_kbase.ko" >&2
echo "  dmesg | grep -i mali       # look for 'Probed as mali0'" >&2
echo "  ls /dev/mali0" >&2
echo "Then to run individual P0 tests:" >&2
echo "  /mnt/mali-p0/bin/001_alloc_free" >&2
echo "Press Ctrl+C then check the QEMU window to exit." >&2
echo >&2

# Share the P0 binaries through 9p so they can be run from the guest.
SHARE_DIR="$RUN/share"
mkdir -p "$SHARE_DIR/bin" "$SHARE_DIR/logs" "$SHARE_DIR/results"
cp "$DIST/bin"/* "$SHARE_DIR/bin/"

# Boot to a shell (init=/bin/sh) with the 9p share attached. -snapshot keeps the
# decompressed rootfs pristine. -no-reboot lets you reset without clobbering it.
exec "$QEMU" \
    -machine "$MACHINE" -cpu "$CPU" -m "$MEMORY" -smp "$SMP" \
    -nographic \
    -snapshot \
    -no-reboot \
    -kernel "$CACHE/Image" \
    -dtb "$DIST/virt-mali.dtb" \
    -append "console=ttyAMA0 root=/dev/vda rw init=/bin/sh" \
    -drive "if=virtio,format=raw,file=$CACHE/rootfs.ext4" \
    -virtfs "local,path=$SHARE_DIR,mount_tag=mali-p0,security_model=none,id=mali-p0" \
    "$@"
