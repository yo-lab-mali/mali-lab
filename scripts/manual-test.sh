#!/bin/bash
#
# manual-test.sh - Interactive manual testing for the P0/P1 suite VM.
#
# Boots the prebuilt dist/ VM to an interactive shell with the Mali driver\n# auto-loaded and /dev/mali0 ready. The 9p share provides P0 test binaries.\n#\n# Usage:\n#   ./scripts/manual-test.sh          boot + interactive shell (driver auto-loaded)\n#   ./scripts/manual-test.sh -i         boot to plain /bin/sh (no driver pre-load)\n#   make manual-test                    same via Makefile\n#\n# Note on P1 tests: KCPU, CQS/fences, and SAME_VA/alias are not prebuilt in\n# the portable lab. They require a kernel tree:\n#   KERNEL_DIR=./work/linux make tests && make test-p1-qemu\n#\n
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

# Default: embed a helper init script that loads Mali and drops to a shell.
# The script is written *inside* the rootfs ext4 image so the kernel can run it
# as the init process. -snapshot mode keeps the outer ext4 pristine between boots;
# the init script is embedded into the base ext4, not the snapshot overlay.
EMBED_INIT=true
[[ "${1:-}" == "-i" ]] && EMBED_INIT=false

if [[ "$EMBED_INIT" == "true" ]]; then
    INIT_PATH="$CACHE/mali-manual-init"
    cat > "$INIT_PATH" <<'INITEOF'
#!/bin/sh
# mali-manual-init: mount basics, load Mali driver, start a shell.
# This is PID 1 inside the guest.
export PS1="mali-manual> "
echo "[mali-manual] Mounting proc, sys, dev..."
mount -t proc proc     /proc 2>/dev/null || true
mount -t sysfs sys    /sys   2>/dev/null || true
mount -t devtmpfs dev /dev   2>/dev/null || true

echo "[mali-manual] Loading Mali driver..."
if [ -f /lib/modules/mali_kbase.ko ]; then
    if insmod /lib/modules/mali_kbase.ko; then
        echo "[mali-manual] Mali driver loaded successfully!"
    else
        echo "[mali-manual] ERROR: Mali driver load failed" >&2
    fi
else
    echo "[mali-manual] WARNING: /lib/modules/mali_kbase.ko not found" >&2
fi

echo "[mali-manual] Checking for /dev/mali0..."
sleep 1
if [ -e /dev/mali0 ]; then
    echo "[mali-manual] SUCCESS: /dev/mali0 exists"
    ls -la /dev/mali0
else
    echo "[mali-manual] WARNING: /dev/mali0 not found" >&2
fi

echo
echo "[mali-manual] Mali dmesg output:"
dmesg | grep -i mali || echo "(no mali dmesg)"

echo
echo "[mali-manual] Interactive shell ready. Type 'exit' to power off."
echo "[mali-manual] P0 test binaries available at /mnt/mali-p0/bin/"
echo "[mali-manual] P1 tests require kernel sources (see host README)."
exec /bin/sh
INITEOF
    chmod +x "$INIT_PATH"

    # Embed the init script into the rootfs ext4 image by mounting it loopback.
    INIT_REL="usr/local/bin/mali-manual-init"
    MNT=$(mktemp -d)
    if sudo mount -o loop "$CACHE/rootfs.ext4" "$MNT" 2>/dev/null; then
        # Re-embed every boot in case the base image was refreshed.
        sudo cp "$INIT_PATH" "$MNT/$INIT_REL"
        sudo chmod +x "$MNT/$INIT_REL"
        sync
        sudo umount "$MNT"
    fi
    rmdir "$MNT" 2>/dev/null || true
    INIT_ARG="init=/$INIT_REL"
else
    INIT_ARG="init=/bin/sh"
fi

# Share the P0 binaries through 9p so they can be run from the guest.
SHARE_DIR="$RUN/share"
mkdir -p "$SHARE_DIR/bin" "$SHARE_DIR/logs" "$SHARE_DIR/results"
cp "$DIST/bin"/* "$SHARE_DIR/bin/"

cat <<EOF
Booting QEMU guest...
  Image: $CACHE/Image
  RootFS: $CACHE/rootfs.ext4
  DTB: $DIST/virt-mali.dtb
  Init: $INIT_ARG

Driver will $([[ "$EMBED_INIT" == "true" ]] && echo "auto-load Mali at boot" || echo "NOT auto-load (use -i to disable)")
P0 test binaries shared via 9p at /mnt/mali-p0/bin/
P1 tests require kernel sources (not prebuilt in dist/).
Press Ctrl+A X to exit QEMU, or type 'exit' in the guest shell.
EOF
echo >&2

# Boot. -snapshot keeps the decompressed rootfs pristine between boots.
exec "$QEMU" \
    -machine "$MACHINE" -cpu "$CPU" -m "$MEMORY" -smp "$SMP" \
    -nographic \
    -snapshot \
    -no-reboot \
    -kernel "$CACHE/Image" \
    -dtb "$DIST/virt-mali.dtb" \
    -append "console=ttyAMA0 root=/dev/vda rw $INIT_ARG" \
    -drive "if=virtio,format=raw,file=$CACHE/rootfs.ext4" \
    -virtfs "local,path=$SHARE_DIR,mount_tag=mali-p0,security_model=none,id=mali-p0" \
    "$@"
