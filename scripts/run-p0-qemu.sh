#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/configs/qemu-aarch64.env"

KERNEL="${KERNEL:-$ROOT/build/kernel/Image}"
ROOTFS="${ROOTFS:-$ROOT/build/rootfs/rootfs.ext4}"
SHARE="$ROOT/build/p0-guest-share"
RESULTS="$ROOT/results/p0-qemu-results.json"
P0_TEST_TIMEOUT_SEC="${P0_TEST_TIMEOUT_SEC:-30}"

[[ -x "$ROOT/scripts/build-tests.sh" ]] || { echo "error: build-tests.sh missing" >&2; exit 1; }
[[ -f "$KERNEL" ]] || { echo "error: missing kernel: $KERNEL" >&2; exit 1; }
[[ -f "$ROOTFS" ]] || { echo "error: missing rootfs: $ROOTFS" >&2; exit 1; }
[[ "$P0_TEST_TIMEOUT_SEC" =~ ^[1-9][0-9]*$ ]] || { echo "error: P0_TEST_TIMEOUT_SEC must be a positive integer" >&2; exit 1; }
command -v "$QEMU" >/dev/null || { echo "error: QEMU not found: $QEMU" >&2; exit 1; }

"$ROOT/scripts/build-tests.sh"
rm -rf "$SHARE"
mkdir -p "$SHARE/bin" "$SHARE/results" "$SHARE/logs"
cp "$ROOT/build/tests/001_alloc_free" \
   "$ROOT/build/tests/002_alloc_mmap" \
   "$ROOT/build/tests/003_mmap_unmap" \
   "$ROOT/build/tests/004_free_before_unmap" \
   "$ROOT/build/tests/001_cookie_lifecycle" \
   "$ROOT/build/tests/003_vma_lifecycle" \
   "$ROOT/build/tests/001_queue_bind" \
   "$ROOT/build/tests/002_user_io_map" "$SHARE/bin/"
chmod 0755 "$SHARE/bin"/*
rm -f "$RESULTS" "$SHARE/results/p0-results.json"

args=(
  -machine "$MACHINE"
  -cpu "$CPU"
  -m "$MEMORY"
  -smp "$SMP"
  -nographic
  -no-reboot
  -kernel "$KERNEL"
  -append "console=ttyAMA0 root=/dev/vda rw init=/usr/local/bin/mali-p0-guest mali_p0_timeout=$P0_TEST_TIMEOUT_SEC"
  -drive "if=virtio,format=raw,file=$ROOTFS"
  -virtfs "local,path=$SHARE,mount_tag=mali-p0,security_model=none,id=mali-p0"
)
if [[ -n "${QEMU_DTB:-}" ]]; then
  [[ -f "$QEMU_DTB" ]] || { echo "error: QEMU_DTB does not exist: $QEMU_DTB" >&2; exit 1; }
  args+=( -dtb "$QEMU_DTB" )
fi

set +e
"$QEMU" "${args[@]}"
qemu_rc=$?
set -e

if [[ -f "$SHARE/results/p0-results.json" ]]; then
  cp "$SHARE/results/p0-results.json" "$RESULTS"
else
  cat > "$RESULTS" <<JSON
{"schema_version":2,"runner":"run-p0-qemu.sh","status":"infra_error","qemu_exit_code":$qemu_rc,"tests":[],"summary":{"pass":0,"skip":0,"fail":0,"timeout":0,"crash":0,"infra_error":1},"infrastructure_errors":[{"code":"guest_result_missing","message":"guest did not produce p0-results.json"}]}
JSON
fi

printf 'P0 guest results: %s\n' "$RESULTS"
cat "$RESULTS"

VALIDATOR="$ROOT/scripts/validate-p0-results.py"
VALIDATION_REPORT="$ROOT/results/p0-qemu-validation.json"
if [[ ! -x "$VALIDATOR" ]]; then
  cat > "$VALIDATION_REPORT" <<JSON
{"schema_version":1,"status":"infra_error","infrastructure_errors":[{"code":"validator_missing","message":"host-side P0 result validator is missing: $VALIDATOR"}]}
JSON
  echo "error: host-side P0 result validator is missing: $VALIDATOR" >&2
  exit 2
fi

set +e
python3 "$VALIDATOR" "$RESULTS"
validation_rc=$?
set -e
if [[ $validation_rc -ne 0 ]]; then
  cat > "$VALIDATION_REPORT" <<JSON
{"schema_version":1,"status":"infra_error","infrastructure_errors":[{"code":"result_validation_failed","message":"guest P0 result failed host-side schema/consistency validation","result":"$RESULTS"}]}
JSON
  echo "error: guest P0 result failed host-side validation; see $VALIDATION_REPORT" >&2
  exit 2
fi

cat > "$VALIDATION_REPORT" <<JSON
{"schema_version":1,"status":"pass","result":"$RESULTS","message":"guest P0 result passed host-side validation"}
JSON

# A clean QEMU exit and a valid guest result are required before the run can
# be marked successful. Test failures remain represented inside the JSON.
if [[ $qemu_rc -ne 0 ]]; then
  exit "$qemu_rc"
fi
exit 0
