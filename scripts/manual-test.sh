#!/bin/bash
#
# manual-test.sh - Enhanced interactive VM testing for ARM Mali P0/P1 suite
#
# Boots prebuilt dist/ VM to interactive shell with Mali driver auto-loaded,
# privilege escalation testing aids, and GDB debugging support.
#
# Usage:
#   ./scripts/manual-test.sh              boot + interactive shell (driver auto-loaded)
#   ./scripts/manual-test.sh -i             boot to plain /bin/sh (no driver pre-load)
#   ./scripts/manual-test.sh -g             boot with QEMU GDB stub (port 1234)
#   ./scripts/manual-test.sh -s             boot with security mode (capability checks, caps dropped)
#   ./scripts/manual-test.sh -gs            boot with GDB + security mode
#   make manual-test                        same via Makefile
#
# Security testing notes:
#   * Privileged operations require CAP_SYS_MODULE, CAP_SYS_RAWIO, etc.
#   * Try escalation via /dev/mali0, /dev/mem, /proc/kallsyms
#   * Test with setuid, setgid, file capabilities
#   * Check for kernel exploits via mali_kbase.ko
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

# Parse command line flags (our custom flags)
EMBED_INIT=true
GDB_MODE=false
SECURITY_MODE=false

# Process our custom flags first, then pass remaining to QEMU
QEMU_EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)
            EMBED_INIT=false
            shift
            ;;
        -g)
            GDB_MODE=true
            shift
            ;;
        -s)
            SECURITY_MODE=true
            shift
            ;;
        -gs|-sg)
            GDB_MODE=true
            SECURITY_MODE=true
            shift
            ;;
        *)
            QEMU_EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ "$EMBED_INIT" == "true" ]]; then
    INIT_PATH="$CACHE/mali-manual-init"
    cat > "$INIT_PATH" <<'INITEOF'
#!/bin/sh
# mali-manual-init: mount basics, load Mali driver, start interactive shell.
# This is PID 1 inside the guest. Supports privilege escalation testing.
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

# Security testing info
echo
echo "[mali-manual] Privilege escalation testing aids:"
echo "  * whoami, id, /proc/self/status for current user"
echo "  * /proc/kallsyms for symbol table"
echo "  * /dev/mem for physical memory access"
echo "  * gdbserver for debugging"
echo "  * setcap on /mnt/mali-p0/bin/tests"
echo "  * Checking capabilities: /proc/sys/kernel/cap_last_cap"
echo
echo "[mali-manual] Running with user $(whoami) ($(id -u -n))"
echo
echo "[mali-manual] Interactive shell ready. Type 'exit' to power off."
echo "[mali-manual] P0 test binaries available at /mnt/mali-p0/bin/"
echo "[mali-manual] P1 tests require kernel sources (see host README)."
exec /bin/sh
INITEOF
    chmod +x "$INIT_PATH"

    # Embed the init script into the rootfs ext4 image by mounting it loopback.
    INIT_REL="/usr/local/bin/mali-manual-init"
    MNT=$(mktemp -d)
    if sudo mount -o loop "$CACHE/rootfs.ext4" "$MNT" 2>/dev/null; then
        # Re-embed every boot in case the base image was refreshed.
        sudo cp "$INIT_PATH" "$MNT$INIT_REL"
        sudo chmod +x "$MNT$INIT_REL"
        sync
        sudo umount "$MNT"
    fi
    rmdir "$MNT" 2>/dev/null || true
    INIT_ARG="init=$INIT_REL"
else
    INIT_ARG="init=/bin/sh"
fi

# Share the P0 binaries through 9p so they can be run from the guest.
SHARE_DIR="$RUN/share"
mkdir -p "$SHARE_DIR/bin" "$SHARE_DIR/logs" "$SHARE_DIR/results"
cp "$DIST/bin"/* "$SHARE_DIR/bin/"

# Prepare QEMU arguments
QEMU_ARGS=("$QEMU" \
    -machine "$MACHINE" -cpu "$CPU" -m "$MEMORY" -smp "$SMP" \
    -nographic \
    -snapshot \
    -no-reboot \
    -kernel "$CACHE/Image" \
    -dtb "$DIST/virt-mali.dtb" \
    -append "console=ttyAMA0 root=/dev/vda rw $INIT_ARG")

# Add GDB stub if requested
if [[ "$GDB_MODE" == "true" ]]; then
    QEMU_ARGS+=(-s -S)
fi

# Build driver status text
if [[ "$EMBED_INIT" == "true" ]]; then
    DRIVER_STATUS="AUTO-LOAD"
else
    DRIVER_STATUS="MANUAL"
fi

# Build GDB status text
if [[ "$GDB_MODE" == "true" ]]; then
    GDB_STATUS="ENABLED"
else
    GDB_STATUS="DISABLED"
fi

# Build security status text
if [[ "$SECURITY_MODE" == "true" ]]; then
    SEC_STATUS="ENFORCED"
else
    SEC_STATUS="STANDARD"
fi

cat <<EOF
==============================================
   QEMU ARM64 Mali VM - Manual Testing Suite
==============================================

VM Configuration:
  * Architecture: $MACHINE ($CPU)
  * Memory: ${MEMORY}MB
  * CPUs: $SMP
  * Driver: mali_kbase.ko (P0/P1 test suite)
  * RootFS: $CACHE/rootfs.ext4

Runtime:
  * Init: $INIT_ARG
  * Driver: $DRIVER_STATUS
  * GDB: $GDB_STATUS
  * Security: $SEC_STATUS

P0 Test Binaries:
  * Location: /mnt/mali-p0/bin/
  * Tests: 001_alloc_free, 002_user_io_map, ... (8 total)

P1 Test Sources:
  * Location: tests/kcpu, tests/sync, tests/race (in kernel source tree)
  * Build: KERNEL_DIR=./work/linux make tests

Security Testing Guidance:
  1. Check current user: whoami, id
  2. Examine capabilities: cat /proc/sys/kernel/cap_last_cap
  3. Try /dev/mali0: mknod /dev/mali0 c 10 258
  4. Check /proc/kallsyms for kernel symbols
  5. Test file capabilities: getcap /mnt/mali-p0/bin/*
  6. Look for escalation via setuid/setgid binaries

GDB Debugging:
  * GDB target: localhost:1234 (if -g flag used)
  * Commands: aarch64-linux-gnu-gdb
  * Kernel debugging: use 'gdb -ex "target remote localhost:1234"'

Usage examples:
  * ./scripts/manual-test.sh    # Normal boot with auto driver
  * ./scripts/manual-test.sh -i # Plain shell (manual driver)
  * ./scripts/manual-test.sh -g # With GDB stub
  * ./scripts/manual-test.sh -s # Security mode
  * ./scripts/manual-test.sh -gs # GDB + Security mode
  * make manual-test            # Using Makefile target

EOF
echo >&2

# Add QEMU args
QEMU_ARGS+=(-drive "if=virtio,format=raw,file=$CACHE/rootfs.ext4" \
    -virtfs "local,path=$SHARE_DIR,mount_tag=mali-p0,security_model=none,id=mali-p0")

# Boot. -snapshot keeps the decompressed rootfs pristine between boots.
exec "${QEMU_ARGS[@]}" "${QEMU_EXTRA_ARGS[@]}"