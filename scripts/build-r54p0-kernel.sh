#!/usr/bin/env bash
#
# build-r54p0-kernel.sh - end-to-end r54p0 kernel build.
#
# Unlike scripts/integrate-mali.sh and scripts/fetch-kernel.sh (both deliberate
# placeholders), this performs every step needed to produce a bootable Image
# with the No-Mali Kbase module:
#
#   1. fetch   - download a pinned Linux LTS source tree
#   2. integrate- copy the verified r54p0 DDK into the kernel tree and wire
#                it into drivers/gpu/Makefile + drivers/video/Kconfig
#   3. config  - defconfig, THEN overlay the No-Mali fragment, THEN olddefconfig
#   4. gate    - assert the symbols the driver hard-requires actually survived
#   5. build   - Image + modules
#
# Usage:
#   ./scripts/build-r54p0-kernel.sh              # all stages
#   ./scripts/build-r54p0-kernel.sh fetch
#   ./scripts/build-r54p0-kernel.sh integrate config gate build
#   KVER=6.6.100 ./scripts/build-r54p0-kernel.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="${KERNEL_DIR:-$ROOT/work/linux}"
MALI_UNPACK="${MALI_UNPACK:-$ROOT/work/mali-r54p0}"
OUT="${KERNEL_OUT:-$ROOT/build/kernel}"

# Resolve the DDK archive through the pinned release/MD5 in configs/r54p0.env so
# the build consumes the same verified artifact scripts/verify-r54p0.sh checks,
# rather than a hand-named copy under driver/.
if [[ -z "${MALI_ARCHIVE:-}" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/configs/r54p0.env"
  MALI_ARCHIVE="$ROOT/downloads/${MALI_RELEASE}.tar.gz"
fi

# Pinned rather than "latest" so a result is reproducible and can be recorded in
# docs/findings.md. r54p0 carries feature guards spanning 5.9 .. 6.13+, so this
# stays inside the range the DDK has actually been built against.
KVER="${KVER:-6.6.158}"
KSRC_URL="${KSRC_URL:-https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz}"
TARBALL="${TARBALL:-$ROOT/work/linux-$KVER.tar.xz}"

ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
MAKE="${MAKE:-make}"
JOBS="${JOBS:-$(nproc)}"
CONFIG_SRC="${CONFIG_SRC:-$ROOT/kernel/config/qemu-aarch64-r54p0.config}"

export ARCH CROSS_COMPILE

log()  { printf '\n=== %s ===\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

kmake() { "$MAKE" -C "$KDIR" "$@"; }

# A packaged lab has no kernel tree: the sources are deleted once the artifacts
# exist, because dist/ is the deliverable and work/ is 3.3 GB of rebuildable
# input. Say so up front rather than letting a stage fail on a missing Makefile.
require_sources() {
  if [[ ! -f "$KDIR/Makefile" ]]; then
    cat >&2 <<EOF
error: no kernel source tree at $KDIR

This looks like a results-only lab. The kernel tree, the DDK archive and the
rootfs downloads are deleted after packaging, because dist/ is self-contained:
nothing in it is derived from them at run time.

  to run the existing lab:      ./dist/run.sh
  to rebuild the tests only:    make tests   (uses dist/headers automatically)

To rebuild the kernel from scratch you need the sources back, which means
re-fetching the pinned Linux tree and re-integrating the MD5-verified DDK. That
is a full rebuild of the step documented in docs/build.md.
EOF
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# 1. fetch
# ---------------------------------------------------------------------------
stage_fetch() {
  if [[ -f "$KDIR/Makefile" ]]; then
    info "kernel tree already present: $KDIR"
    return 0
  fi
  [[ -f "$TARBALL" ]] || {
    info "downloading $KSRC_URL"
    curl -fL --retry 3 -o "$TARBALL.part" "$KSRC_URL" \
      || die "download failed: $KSRC_URL"
    mv "$TARBALL.part" "$TARBALL"
  }
  info "extracting $KVER -> $KDIR"
  rm -rf "$KDIR" "$ROOT/work/linux-$KVER"
  tar xf "$TARBALL" -C "$ROOT/work"
  [[ -d "$ROOT/work/linux-$KVER" ]] || die "unexpected tarball layout"
  mv "$ROOT/work/linux-$KVER" "$KDIR"
  info "kernel $KVER at $KDIR"
}

# ---------------------------------------------------------------------------
# 2. integrate
#
# This overwrites include/linux/version_compat_defs.h and adds drivers/base/arm,
# drivers/xen/arm and drivers/hwtracing/coresight/mali. It is therefore only
# safe on a tree that has not been integrated before.
# ---------------------------------------------------------------------------
stage_integrate() {
  [[ -f "$KDIR/Makefile" ]] || die "no kernel tree at $KDIR (run: fetch)"
  [[ -f "$MALI_ARCHIVE" ]] || die "missing $MALI_ARCHIVE"

  if [[ -e "$KDIR/drivers/gpu/arm/midgard/Kbuild" ]]; then
    info "r54p0 already integrated into $KDIR"
    return 0
  fi

  if [[ ! -d "$MALI_UNPACK/driver/product/kernel" ]]; then
    info "unpacking $MALI_ARCHIVE"
    rm -rf "$MALI_UNPACK"
    mkdir -p "$MALI_UNPACK"
    tar xzf "$MALI_ARCHIVE" -C "$MALI_UNPACK"
  fi
  local src="$MALI_UNPACK/driver/product/kernel"
  [[ -d "$src/drivers/gpu/arm/midgard" ]] || die "unexpected archive layout: $src"

  info "copying $src/* -> $KDIR/"
  cp -a "$src/." "$KDIR/"

  info "wiring drivers/gpu/Makefile"
  grep -q 'CONFIG_MALI_MIDGARD' "$KDIR/drivers/gpu/Makefile" \
    || echo 'obj-$(CONFIG_MALI_MIDGARD) += arm/' >> "$KDIR/drivers/gpu/Makefile"

  info "wiring drivers/video/Kconfig"
  if ! grep -q 'drivers/gpu/arm/Kconfig' "$KDIR/drivers/video/Kconfig"; then
    sed -i '$i source "drivers/gpu/arm/Kconfig"' "$KDIR/drivers/video/Kconfig"
  fi

  [[ -f "$KDIR/drivers/gpu/arm/Kconfig" ]] || die "drivers/gpu/arm/Kconfig missing after copy"
  info "integration done"
}

# ---------------------------------------------------------------------------
# 3. config
#
# Order matters. olddefconfig assigns every unlisted symbol its Kconfig default
# (usually n); it does not start from defconfig. Copying the ~20-line No-Mali
# fragment straight to .config therefore yields a near-empty kernel and the
# driver's Kbuild hard-errors on missing CONFIG_DMA_SHARED_BUFFER & friends.
# So: full defconfig baseline, then overlay, then resolve.
# ---------------------------------------------------------------------------
stage_config() {
  [[ -f "$KDIR/Makefile" ]] || die "no kernel tree at $KDIR (run: fetch)"
  [[ -f "$CONFIG_SRC" ]] || die "missing config fragment: $CONFIG_SRC"

  if [[ ! -f "$KDIR/.config" || "${FORCE_CONFIG:-0}" == 1 ]]; then
    info "generating arm64 defconfig baseline"
    kmake defconfig
  fi

  # Drop any previous copy of the fragment's own lines before re-applying, so
  # re-running this stage is idempotent instead of growing .config by another
  # copy every time. Matching on content is the only option available:
  # olddefconfig rewrites .config and discards comments, so a marker comment
  # cannot survive to identify the block.
  grep -Fxv -f "$CONFIG_SRC" "$KDIR/.config" > "$KDIR/.config.new" || true
  [[ -s "$KDIR/.config.new" ]] || die "refusing to continue: .config rewrite produced nothing"
  mv "$KDIR/.config.new" "$KDIR/.config"

  info "overlaying No-Mali fragment: $CONFIG_SRC"
  {
    printf '\n# r54p0 no-Mali overlay (from %s)\n' "$CONFIG_SRC"
    cat "$CONFIG_SRC"
  } >> "$KDIR/.config"

  kmake olddefconfig
  info "config resolved"
}

# ---------------------------------------------------------------------------
# 4. gate
#
# drivers/gpu/arm/midgard/Kbuild calls $(error ...) on missing prerequisites, so
# a missing symbol is a link-time failure after a 30 minute build. Check up
# front. See docs/build.md.
# ---------------------------------------------------------------------------
stage_gate() {
  [[ -f "$KDIR/.config" ]] || die "no .config (run: config)"
  local cfg="$KDIR/.config"
  local rc=0

  # Required by drivers/gpu/arm/midgard/Kbuild / drivers/gpu/arm/Kbuild.
  local required=(
    CONFIG_MALI_MIDGARD=m
    CONFIG_MALI_CSF_SUPPORT=y
    CONFIG_MALI_NO_MALI=y
    CONFIG_MALI_EXPERT=y
    CONFIG_DMA_SHARED_BUFFER=y
    CONFIG_PM_DEVFREQ=y
    CONFIG_DEVFREQ_THERMAL=y
    CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y
    CONFIG_FW_LOADER=y
  )
  for sym in "${required[@]}"; do
    if grep -qx "$sym" "$cfg"; then
      info "ok   $sym"
    else
      printf '  MISS %s\n' "$sym" >&2
      rc=1
    fi
  done

  # String-valued symbols must survive olddefconfig verbatim.
  for sym in CONFIG_MALI_NO_MALI_DEFAULT_GPU CONFIG_MALI_PLATFORM_NAME; do
    if grep -qE "^$sym=" "$cfg"; then
      info "ok   $(grep -E "^$sym=" "$cfg")"
    else
      printf '  MISS %s\n' "$sym" >&2
      rc=1
    fi
  done

  # REAL_HW must stay off or the dummy model is not used.
  if grep -qx '# CONFIG_MALI_REAL_HW is not set' "$cfg"; then
    info "ok   CONFIG_MALI_REAL_HW disabled"
  else
    printf '  MISS CONFIG_MALI_REAL_HW must be disabled\n' >&2
    rc=1
  fi

  [[ $rc -eq 0 ]] || die "config gate failed; refusing to build (see above)"
  info "config gate passed"
}

# ---------------------------------------------------------------------------
# 5. build
# ---------------------------------------------------------------------------
stage_build() {
  stage_gate
  mkdir -p "$OUT"
  info "building with -j$JOBS (this takes a while)"
  kmake -j"$JOBS" Image modules

  local img="$KDIR/arch/$ARCH/boot/Image"
  local ko
  ko="$(find "$KDIR/drivers/gpu/arm/midgard" -name 'mali_kbase.ko' -print -quit 2>/dev/null || true)"
  [[ -f "$img" ]] || die "Image not produced at $img"
  cp "$img" "$OUT/Image"

  [[ -n "$ko" ]] || die "mali_kbase.ko not found - driver did not build"
  cp "$ko" "$OUT/mali_kbase.ko"

  cat > "$OUT/manifest.txt" <<EOF
kernel_version=$KVER
kernel_url=$KSRC_URL
kernel_dir=$KDIR
mali_archive=$MALI_ARCHIVE
arch=$ARCH
cross_compile=$CROSS_COMPILE
image=$OUT/Image
module=$OUT/mali_kbase.ko
EOF
  log "build complete"
  info "Image:      $OUT/Image"
  info "mali_kbase: $OUT/mali_kbase.ko"
  info "manifest:   $OUT/manifest.txt"
}

# ---------------------------------------------------------------------------
main() {
  require_sources

  command -v "$CROSS_COMPILE"gcc >/dev/null 2>&1 \
    || die "missing cross compiler: ${CROSS_COMPILE}gcc (apt install gcc-aarch64-linux-gnu)"

  local stages=("$@")
  [[ ${#stages[@]} -eq 0 ]] && stages=(fetch integrate config gate build)

  local s
  for s in "${stages[@]}"; do
    case "$s" in
      fetch)     log "STAGE 1/5 fetch";     stage_fetch ;;
      integrate) log "STAGE 2/5 integrate"; stage_integrate ;;
      config)    log "STAGE 3/5 config";    stage_config ;;
      gate)      log "STAGE 4/5 gate";      stage_gate ;;
      build)     log "STAGE 5/5 build";     stage_build ;;
      *) die "unknown stage: $s" ;;
    esac
  done
}

main "$@"
