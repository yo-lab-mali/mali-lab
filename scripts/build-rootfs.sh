#!/usr/bin/env bash
#
# build-rootfs.sh - build the AArch64 guest rootfs consumed by
# scripts/run-p0-qemu.sh, which expects a raw ext4 image at
# build/rootfs/rootfs.ext4 and boots it with init=/usr/local/bin/mali-p0-guest.
#
# Layout produced:
#   /usr/local/bin/mali-p0-guest   PID 1 runner (from rootfs/overlay)
#   /lib/modules/mali_kbase.ko     the module built by build-r54p0-kernel.sh
#   /usr/bin/busybox               supplies sh, insmod, poweroff, halt
#
# Design notes:
#   * mke2fs -d populates the image from a staging directory, so no loop mount
#     and no root are required.
#   * busybox-static is added because ubuntu-base ships neither insmod nor
#     poweroff/halt, and mali-p0-guest is PID 1: when it cannot power off, the
#     kernel panics on init exit instead of shutting down cleanly.
#   * The P0 tests are dynamically linked against glibc, so a real glibc root
#     (ubuntu-base) is required rather than a busybox-only image.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/rootfs"
STAGE="$BUILD/stage"
IMG="$BUILD/rootfs.ext4"
DL="$ROOT/work/rootfs-dl"
KO="${MALI_KO:-$ROOT/build/kernel/mali_kbase.ko}"
OVERLAY="$ROOT/rootfs/overlay"

# Pinned with checksums so the image is reproducible and a corrupted or
# substituted download fails loudly instead of producing a mystery boot.
UBUNTU_BASE_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-arm64.tar.gz"
UBUNTU_BASE_SHA256="7b2dced6dd56ad5e4a813fa25c8de307b655fdabc6ea9213175a92c48dabb048"
BUSYBOX_URL="http://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3_arm64.deb"
BUSYBOX_SHA256="1a8c03948f99dfbb90efd93d9214418b416ac0737ed4c90938ebbcd645f10682"

# Applets busybox must provide because ubuntu-base has no equivalent.
BUSYBOX_APPLETS="sh insmod poweroff halt reboot"

log()  { printf '\n=== %s ===\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

fetch() {
  local url="$1" want="$2" dest="$3" got
  mkdir -p "$(dirname "$dest")"
  if [[ ! -f "$dest" ]]; then
    info "downloading $(basename "$dest")"
    curl -fL --retry 3 -o "$dest.part" "$url" || die "download failed: $url"
    mv "$dest.part" "$dest"
  fi
  got="$(sha256sum "$dest" | awk '{print $1}')"
  [[ "$got" == "$want" ]] || die "sha256 mismatch for $(basename "$dest"): want $want got $got"
  info "verified $(basename "$dest")"
}

for t in tar dpkg-deb mke2fs curl; do
  command -v "$t" >/dev/null || die "missing required tool: $t"
done
if [[ ! -f "$KO" ]]; then
  # A packaged lab has no kernel tree, so 'make kernel' cannot produce the
  # module this image is built around. A module shipped in dist/ is the same
  # bytes and can be rebuilt from, which is the common case worth naming.
  cat >&2 <<EOF
error: missing driver module: $KO

The rootfs embeds the module at /lib/modules/mali_kbase.ko and cannot be built
without it. Either rebuild it (scripts/build-r54p0-kernel.sh build, which needs
the kernel tree and the DDK) or, if dist/ has been packaged, reuse the copy
there:

  MALI_KO=./dist/mali_kbase.ko ./scripts/build-rootfs.sh
EOF
  exit 1
fi
[[ -d "$OVERLAY" ]] || die "missing overlay directory: $OVERLAY"

BASE_TGZ="$DL/ubuntu-base-arm64.tar.gz"
BUSYBOX_DEB="$DL/busybox-static_arm64.deb"

log "1/6 fetch pinned userspace"
fetch "$UBUNTU_BASE_URL" "$UBUNTU_BASE_SHA256" "$BASE_TGZ"
fetch "$BUSYBOX_URL"      "$BUSYBOX_SHA256"      "$BUSYBOX_DEB"

log "2/6 stage ubuntu-base arm64"
# A previous run may have left the tree root-owned via the chown below.
if ! rm -rf "$STAGE" 2>/dev/null; then
  sudo -n rm -rf "$STAGE" || die "cannot clear $STAGE (root-owned leftovers and no passwordless sudo)"
fi
mkdir -p "$STAGE"
tar xzf "$BASE_TGZ" -C "$STAGE"
# Merged-/usr layout: bin -> usr/bin and sbin -> usr/sbin are symlinks in the
# tarball, so anything written under bin/ or sbin/ lands in usr/ automatically.
[[ -L "$STAGE/bin" ]] || die "expected $STAGE/bin to be a merged-usr symlink"

log "3/6 install busybox-static applets"
dpkg-deb -x "$BUSYBOX_DEB" "$STAGE"
BUSYBOX="$STAGE/usr/bin/busybox"
[[ -x "$BUSYBOX" ]] || BUSYBOX="$STAGE/bin/busybox"
[[ -x "$BUSYBOX" ]] || die "busybox binary not found after extraction"
for applet in $BUSYBOX_APPLETS; do
  # Never shadow a real binary that ubuntu-base already provides.
  if [[ -e "$STAGE/usr/bin/$applet" || -L "$STAGE/usr/bin/$applet" ]]; then
    info "keep existing /usr/bin/$applet"
    continue
  fi
  ln -sf busybox "$STAGE/usr/bin/$applet"
  info "linked /usr/bin/$applet -> busybox"
done
# busybox dispatches on argv[0], so /bin/sh must resolve to the binary itself.
[[ -e "$STAGE/usr/bin/sh" ]] || die "/bin/sh is missing; the guest runner cannot start"

log "4/6 restore merged-usr layout"
# dpkg-deb -x cannot write through the merged-usr symlinks, so it replaces them
# with real directories. That silently breaks every absolute path the guest
# resolves through /bin, /sbin and /lib. /bin/sh in particular is the shebang
# interpreter the kernel needs in order to exec mali-p0-guest at all: without
# it the boot dies with "Requested init ... failed (error -2)", i.e. ENOENT.
# Relocate whatever dpkg left behind and put the symlinks back.
merged_usr_link() {
  local link="$1" target="$2"
  [[ -L "$STAGE/$link" ]] && return 0
  [[ -d "$STAGE/$target" ]] || return 0
  if [[ -d "$STAGE/$link" ]]; then
    find "$STAGE/$link" -mindepth 1 -maxdepth 1 -exec mv -t "$STAGE/$target" {} +
    rm -rf "$STAGE/$link"
  fi
  ln -sfn "$target" "$STAGE/$link"
  info "restored /$link -> $target"
}
merged_usr_link bin usr/bin
merged_usr_link sbin usr/sbin
merged_usr_link lib usr/lib
merged_usr_link lib64 usr/lib64

# Fail here rather than as a kernel panic ten minutes into a QEMU run.
for must in /bin/sh /sbin /lib; do
  [[ -e "$STAGE$must" ]] || die "missing $must in the staged rootfs"
done
[[ -L "$STAGE/bin" && -L "$STAGE/lib" ]] || die "merged-usr layout not restored"
# The loader must resolve, or every dynamically linked binary execs to ENOENT.
for so in "$STAGE/lib/ld-linux-aarch64.so.1" "$STAGE/usr/lib/aarch64-linux-gnu/libc.so.6"; do
  [[ -e "$so" ]] || die "missing runtime library: $so"
done

log "5/6 install overlay and driver module"
cp -a "$OVERLAY/." "$STAGE/"
install -D -m 0644 "$KO" "$STAGE/lib/modules/mali_kbase.ko"
info "installed $(basename "$KO") -> /lib/modules/"
[[ -e "$STAGE/lib/modules/mali_kbase.ko" ]] || die "mali_kbase.ko did not land in /lib/modules"
[[ -f "$STAGE/usr/local/bin/mali-p0-guest" ]] || die "overlay did not provide mali-p0-guest"
# The runner is PID 1; it must be executable and not world-writable.
chmod 0755 "$STAGE/usr/local/bin/mali-p0-guest"

# Mount points the PID 1 preamble attaches. The tarball ships the directories
# but mke2fs cannot create device nodes unprivileged; devtmpfs covers /dev.
for d in proc sys dev run tmp; do mkdir -p "$STAGE/$d"; done

log "6/6 prune, size and write ext4 image"
# Documentation, translations and headers are dead weight in a test guest.
# This runs before the chown below, because once the tree is root-owned the
# build user can no longer remove anything from it.
rm -rf "$STAGE/usr/share/doc" "$STAGE/usr/share/man" "$STAGE/usr/share/info" \
       "$STAGE/usr/share/locale" "$STAGE/usr/share/zoneinfo" \
       "$STAGE/usr/include" "$STAGE/usr/src"
used_kb="$(du -sk "$STAGE" | awk '{print $1}')"
# ext4 needs room for its metadata on top of the file payload.
size_mb=$(( used_kb / 1024 + 128 ))
(( size_mb < 512 )) && size_mb=512
info "staged ${used_kb} KiB -> ${size_mb} MiB image"

# mke2fs -d copies the staging tree verbatim and this e2fsprogs silently
# ignores -E root_owner, so the guest would otherwise see every system file as
# uid 1000. Harmless for read/execute, but make it a real rootfs when
# passwordless sudo is available and say so plainly when it is not.
# mke2fs must then also run privileged: the base image contains /root and
# /var/cache/ldconfig as mode 0700 and /etc/.pwd.lock as mode 0600, none of
# which an unprivileged mke2fs can read.
MKFS=(mke2fs)
if sudo -n true 2>/dev/null; then
  sudo -n chown -R 0:0 "$STAGE"
  MKFS=(sudo -n mke2fs)
  info "chown -R 0:0 applied; mke2fs runs privileged to traverse the tree"
else
  info "no passwordless sudo: files stay owned by uid $(id -u) (read/execute is unaffected)"
fi

mkdir -p "$BUILD"
rm -f "$IMG"
truncate -s "${size_mb}M" "$IMG"
# Ownership now comes from the chown above; mke2fs -E root_owner is a no-op
# with -d on e2fsprogs 1.47, so it is deliberately not passed here.
if ! "${MKFS[@]}" -q -t ext4 -F -d "$STAGE" -L mali-rootfs "$IMG" 2>"$BUILD/mke2fs.log"; then
  # Unprivileged mke2fs warns about device nodes it cannot create; that is
  # expected and harmless because devtmpfs populates /dev at boot.
  info "mke2fs reported diagnostics (see $BUILD/mke2fs.log):"
  sed 's/^/    /' "$BUILD/mke2fs.log"
fi
# Ownership and the merged-usr symlinks must be correct in the image, not just
# in the staging tree, so verify the artefact rather than the inputs.
debugfs -R "stat /usr/bin/sh" "$IMG" 2>/dev/null | grep -q 'Inode:' \
  || die "image is missing /usr/bin/sh"
debugfs -R "ls -l /" "$IMG" 2>/dev/null | grep -qE '^ *[0-9]+ +120777 .* bin' \
  || die "image does not have /bin as a symlink"
e2fsck -fn "$IMG" >/dev/null 2>&1 || die "ext4 image failed consistency check"

cat > "$BUILD/manifest.txt" <<EOF
image=$IMG
size_mb=$size_mb
staged_kb=$used_kb
ubuntu_base_url=$UBUNTU_BASE_URL
ubuntu_base_sha256=$UBUNTU_BASE_SHA256
busybox_url=$BUSYBOX_URL
busybox_sha256=$BUSYBOX_SHA256
module=$(basename "$KO")
module_sha256=$(sha256sum "$KO" | awk '{print $1}')
init=/usr/local/bin/mali-p0-guest
EOF

log "rootfs complete"
info "image:   $IMG"
info "manifest:$BUILD/manifest.txt"
info ""
info "Run scripts/run-p0-qemu.sh to boot it and execute the P0 suite."
