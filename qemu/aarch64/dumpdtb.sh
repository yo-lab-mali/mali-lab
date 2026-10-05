#!/usr/bin/env bash
#
# dumpdtb.sh - produce a QEMU virt Device Tree Blob that contains a Mali node.
#
# Why this is required: scripts/run-p0-qemu.sh passes no -dtb, so QEMU supplies
# its built-in virt DTB, which has no Mali node at all. Arm's How-To Guide is
# explicit that in that situation the module loads, `lsmod` shows mali_kbase,
# no dmesg is emitted, and kbase is unusable. On a CONFIG_OF build the driver
# matches only through of_match_table, so the node is what makes it probe.
#
# Method: let QEMU dump its own virt DTB, decompile it, splice in the repo's
# mali-no-mali.dtsi node at the root, and recompile. Run-p0-qemu.sh then picks
# the result up through its existing QEMU_DTB hook.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/configs/qemu-aarch64.env"
DTSI="$ROOT/qemu/aarch64/dt/mali-no-mali.dtsi"
OUTDIR="${DTB_OUTDIR:-$ROOT/build/dtb}"
BASE_DTB="$OUTDIR/virt-base.dtb"
OUT_DTS="$OUTDIR/virt-mali.dts"
OUT_DTB="${QEMU_DTB:-$OUTDIR/virt-mali.dtb}"

log()  { printf '\n=== %s ===\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

for t in dtc "$QEMU"; do
  command -v "$t" >/dev/null || die "missing required tool: $t"
done
[[ -f "$DTSI" ]] || die "missing Mali DT fragment: $DTSI"

mkdir -p "$OUTDIR"

log "1/4 dump QEMU virt DTB"
rm -f "$BASE_DTB"
# dumpdtb makes QEMU write the DTB and exit without booting anything.
"$QEMU" -machine "$MACHINE,dumpdtb=$BASE_DTB" -cpu "$CPU" -smp "$SMP" -m "$MEMORY" \
  -nographic >/dev/null 2>&1 || true
[[ -s "$BASE_DTB" ]] || die "QEMU did not produce $BASE_DTB"
info "$(wc -c <"$BASE_DTB") bytes"

log "2/4 decompile"
dtc -I dtb -O dts -o "$OUT_DTS" "$BASE_DTB" 2>/dev/null
grep -q 'dts-v1/' "$OUT_DTS" || die "decompiled DTB looks wrong"

log "3/4 splice Mali node"
# Insert the fragment's node as a direct child of the root. The fragment is
# written to be self-contained, so textually lifting its node block out keeps
# a single source of truth in dt/mali-no-mali.dtsi.
node="$(awk '/^gpu: gpu@/ {p=1} p {print} p && /^};$/ {exit}' "$DTSI")"
[[ -n "$node" ]] || die "could not extract the gpu node from $DTSI"
info "$(printf '%s\n' "$node" | wc -l) lines: $(printf '%s' "$node" | head -1)"

awk -v node="$node" '
  # dtc requires properties to precede subnodes, so the Mali node must land
  # after the root own properties and before its first child. A child at
  # depth 1 is a single tab, an identifier (optionally with a unit-address),
  # then a brace.
  !done && /^\t[[:alnum:]_#-]+(@[[:alnum:],]+)?[[:space:]]*\{/ { print node; done=1 }
  { print }
' "$OUT_DTS" > "$OUT_DTS.tmp" && mv "$OUT_DTS.tmp" "$OUT_DTS"
grep -q 'arm,mali-midgard' "$OUT_DTS" || die "Mali node was not inserted"

log "4/4 recompile"
dtc -I dts -O dtb -o "$OUT_DTB" "$OUT_DTS" 2>"$OUTDIR/dtc-warnings.log" || {
  sed 's/^/    /' "$OUTDIR/dtc-warnings.log" >&2
  die "dtc failed to rebuild the DTB"
}
info "$(wc -c <"$OUT_DTB") bytes -> $OUT_DTB"

# Fail loudly rather than booting a kernel whose driver will never probe.
if ! dtc -I dtb -O dts "$OUT_DTB" 2>/dev/null | grep -q 'arm,mali-midgard'; then
  die "rebuilt DTB does not contain the Mali node"
fi

cat > "$OUTDIR/manifest.txt" <<EOF
dtb=$OUT_DTB
source_dtb=$BASE_DTB
dtsi=$DTSI
machine=$MACHINE
cpu=$CPU
compatible=arm,mali-midgard
EOF

log "done"
info "export QEMU_DTB=$OUT_DTB"
info "then run scripts/run-p0-qemu.sh"
