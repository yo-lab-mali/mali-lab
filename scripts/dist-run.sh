#!/usr/bin/env bash
#
# dist-run.sh - portable entry point for the results-only lab.
#
# scripts/package-dist.sh copies this file into dist/ next to the artifacts it
# needs. It is deliberately standalone: it resolves every path relative to its
# own location and references nothing in the repository, so the dist/ folder can
# be tarred and run on any host that has qemu-system-aarch64.
#
# Do not edit dist/run.sh. It is generated. Edit this file and re-run
# 'make dist'. The logic here mirrors scripts/run-p0-qemu.sh; if you change one,
# change the other, or the two will silently disagree.
#
# What is different from the in-repo runner, and why:
#   * No cross-compile step. There are no sources, so the P0 binaries ship
#     prebuilt in bin/. scripts/run-p0-qemu.sh rebuilds them from the kernel
#     tree on every run, which is right when the tree is present and fatal when
#     it is not.
#   * -dtb is not optional. With CONFIG_MALI_PLATFORM_NAME="devicetree" Kbase
#     binds only through of_match_table, and without a Mali node in the DTB the
#     module loads, appears in lsmod, prints nothing and never probes. The
#     tests would then all report skip and look like a driver failure.
#   * -snapshot. The packaged rootfs.ext4 is a deliverable and must stay
#     byte-identical, so the guest writes to a temporary overlay instead. Without
#     it every run mutates the image and a second run starts from a dirty
#     filesystem.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/qemu.env"

# BASEP_QUEUE_NR_MMAP_USER_PAGES is irrelevant here; the guest runner decides
# test semantics. These are the 8 binaries mali-p0-guest execs by name.
TESTS=(
  001_alloc_free 002_alloc_mmap 003_mmap_unmap 004_free_before_unmap
  001_cookie_lifecycle 003_vma_lifecycle
  001_queue_bind 002_user_io_map
)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '  %s\n' "$*"; }

IMAGE="$HERE/Image"
ROOTFS="$HERE/rootfs.ext4"
DTB="$HERE/virt-mali.dtb"
RUN="$HERE/.run"
RESULTS="$RUN/results/p0-results.json"
TIMEOUT="${P0_TEST_TIMEOUT_SEC:-30}"

command -v "$QEMU" >/dev/null 2>&1 || die "$QEMU not found on PATH"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "P0_TEST_TIMEOUT_SEC must be a positive integer"
[[ -f "$IMAGE" ]] || die "missing $IMAGE"
[[ -f "$ROOTFS" ]] || die "missing $ROOTFS"
[[ -f "$DTB" ]]   || die "missing $DTB"

for t in "${TESTS[@]}"; do
  [[ -f "$HERE/bin/$t" ]] || die "missing test binary bin/$t"
done

# The guest mounts this over virtio-9p and writes results/ and logs/ into it, so
# it must be writable and must not be the packaged bin/ directory.
rm -rf "$RUN"
mkdir -p "$RUN/bin" "$RUN/results" "$RUN/logs"
install -m 0755 "$HERE/bin/"* "$RUN/bin/"

info "kernel   $IMAGE"
info "rootfs   $ROOTFS (opened with -snapshot; the packaged image is not modified)"
info "dtb      $DTB"
info "tests    ${#TESTS[@]} prebuilt aarch64 binaries"
info "timeout  ${TIMEOUT}s per test"

set +e
"$QEMU" \
  -machine "$MACHINE" -cpu "$CPU" -m "$MEMORY" -smp "$SMP" \
  -nographic \
  -no-reboot \
  -snapshot \
  -kernel "$IMAGE" \
  -dtb "$DTB" \
  -append "console=ttyAMA0 root=/dev/vda rw init=/usr/local/bin/mali-p0-guest mali_p0_timeout=$TIMEOUT" \
  -drive "if=virtio,format=raw,file=$ROOTFS" \
  -virtfs "local,path=$RUN,mount_tag=mali-p0,security_model=none,id=mali-p0"
qemu_rc=$?
set -e

if [[ ! -f "$RESULTS" ]]; then
  die "guest produced no results file (qemu exit $qemu_rc). Check the console above; a mount failure or a kernel panic both land here."
fi

info "results  $RESULTS"
info "logs     $RUN/logs/"

# Pass the summary through without needing jq: the guest writes it on one line
# as {"summary":{"pass":N,"skip":N,...},"infrastructure_errors":[...],"environment":{...},"status":"pass"}
summary="$(sed -n 's/.*"summary":\({[^}]*}\).*/\1/p' "$RESULTS" | tail -1)"
overall="$(sed -n 's/.*"status":"\([a-z_]*\)"[[:space:]]*}$/\1/p' "$RESULTS" | tail -1)"
printf '\nsummary: %s\n' "${summary:-<unparsed>}"
printf 'status : %s\n' "${overall:-<unparsed>}"

# The guest's own exit status already folds fail/timeout/crash/infra into 1, and
# a QEMU non-zero without a results file is handled above.
if [[ "$overall" != "pass" ]]; then
  exit 1
fi
exit "$qemu_rc"