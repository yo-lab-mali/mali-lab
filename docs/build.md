# Build

## Eligibility constraints

The supplied Device Configuration Guidelines make reproducibility on a conforming
configuration a **precondition for bug bounty eligibility**, so these settings are
not optional polish. Only the following deviations from the default kernel
configuration are permitted:

| Option | Constraint |
|---|---|
| `CONFIG_COMPAT` | `y` or `n` |
| `CONFIG_ARM64_4K_PAGES` / `CONFIG_ARM64_16K_PAGES` | exactly one `y`, the other `n` |
| `CONFIG_KASAN*` | any, **except** `CONFIG_KASAN_*_TEST` must be `n` |
| `CONFIG_UBSAN*` | any, **except** `CONFIG_TEST_UBSAN` must be `n` |

The Mali kernel driver supports **64-bit only**. Do not test on a 32-bit kernel or use
32-bit config settings other than `CONFIG_COMPAT`.

Two consequences for this repository:

- The `CONFIG_KASAN_GENERIC`/`CONFIG_KASAN_INLINE` sanitizer configs are permitted, but
  the KASAN self-test variants are not. `kernel/config/qemu-aarch64-kasan.config`
  therefore sets `CONFIG_KASAN_GENERIC=y` without any `*_TEST` variant.
- `kernel/config/qemu-x86_64-kasan.config` must set `CONFIG_KASAN_GENERIC=y` only. Note
  the driver also requires `CONFIG_KASAN_STACK=y` on many 6.x trees; if the kernel
  build warns that stack instrumentation is unavailable, that config fragment needs
  updating rather than enabling a `*_TEST` variant.

Vulnerabilities caused by missing OEM backports, missing patches, or vendor-specific
customizations are **out of scope** and should be reported to the OEM instead.

## Host dependencies

Typical Linux host requirements include:

- git
- make
- gcc/binutils
- cross compiler for AArch64
- QEMU system emulator
- cpio/tar
- an initramfs/rootfs builder
- `dtc` (device-tree-compiler) if building a custom Device Tree blob

The scripts intentionally avoid downloading the Arm driver automatically.

## Flow

`make all` runs all of this in order (`scripts/build-all.sh`):

```text
verify exact r54p0 archive (MD5)
        |
kernel: fetch -> integrate -> config -> gate -> build
        |
build rootfs
        |
build DTB carrying the Mali node
        |
build host test binaries
        |
boot QEMU
```

Stage by stage:

| Target | Effect |
|---|---|
| `make verify` | MD5-check the DDK archive named by `configs/r54p0.env` |
| `make fetch-kernel` | download and unpack the pinned Linux source (`KVER`, default 6.6.158) |
| `make integrate` | copy `driver/product/kernel/` into the tree, wire Kbuild/Makefile/Kconfig |
| `make config` | defconfig, then the No-Mali fragment, then olddefconfig; then gate |
| `make build` | gate, then `make Image modules`; publish `Image`, `mali_kbase.ko`, manifest |
| `make kernel` | the five kernel stages above, in one step |
| `make dtb` | QEMU `virt` DTB with the Mali node spliced in |
| `make rootfs` | ext4 guest image from the pinned Ubuntu base |
| `make tests` | host P0 test binaries |
| `make dist` | collect every artifact into the portable `dist/` lab |

The DTB step is not optional and is therefore part of `make all`. See
"Verifying the probe" below for what happens without it.

All of this lives in `scripts/build-r54p0-kernel.sh`. The per-stage scripts under
`scripts/` are thin delegators kept so existing entry points keep working; keeping
the logic in one place is what stops the config and build stages from drifting
apart.

## Portable lab

`make dist` collects the build outputs into `dist/`, a self-contained folder that
boots and runs the P0 suite with only `qemu-system-aarch64` on the host:

```bash
make dist          # assemble dist/ from build/
dist/run.sh        # run the P0 suite, exit non-zero on any failure
```

```text
dist/
  run.sh, qemu.env   standalone entry point and its machine settings
  Image, rootfs.ext4 the bootable pair
  mali_kbase.ko      the module, also embedded in rootfs at /lib/modules/
  virt-mali.dtb      REQUIRED: no Mali node means the driver never probes
  virt-mali.dts      decompiled form of the above, readable record
  bin/               the 8 prebuilt aarch64 P0 binaries
  headers/           r54p0 UAPI kit, so tests still build offline
  manifest.txt       build provenance: versions, config, host
  SHA256SUMS         standard format, for `sha256sum -c SHA256SUMS`
  .run/              scratch, recreated every run (9p share, results, logs)
```

Roughly 167 MB. Once it is built, `work/` (about 3.9 GB of rebuildable input:
kernel tree, DDK archive, unpacked driver, rootfs downloads) and the 112 MB
`build/rootfs/stage/` staging tree can be deleted. Nothing in `dist/` is derived
from them at run time. `downloads/` keeps the MD5-verified DDK archive as the
provenance record.

`rootfs.ext4` is 512 MB of address space but only about 86 MB of real blocks, so
packaging copies it sparsely. Plain `tar` does **not** preserve holes and expands
it to roughly 588 MB; use `tar -S` to keep the archive at its real size:

```bash
tar -S -cf mali-lab.tar --exclude='dist/.run' dist
```

`dist/run.sh` is generated from `scripts/dist-run.sh` and mirrors
`scripts/run-p0-qemu.sh`; it cannot reference the repository, which is what makes
`dist/` portable, so the two do carry duplicated logic. Change both together. It
differs in three ways that matter:

- No cross-compile step. The P0 binaries ship prebuilt in `bin/`.
- `-dtb` is unconditional. See "Verifying the probe" below.
- `-snapshot`, so the guest writes to a temporary overlay and the packaged
  `rootfs.ext4` stays byte-identical. Without it every run dirties the image and a
  second run starts from a modified filesystem.

### Rebuilding tests without the kernel tree

`headers/` holds `include/uapi` and `include/linux` from the integrated tree,
which is all the test build and the ABI gate read. `make tests` finds it
automatically once `work/` is gone, so this needs no flag:

```bash
make tests                                            # host P0 binaries
KERNEL_DIR=./dist/headers ./scripts/configure-abi-check.sh   # explicit form
```

`include/linux` cannot be dropped: `include/uapi/linux/stddef.h` includes
`<linux/compiler_types.h>`, which exists only there. Verified by building the P0
tests for both aarch64 and the host against this subset alone.

The build scripts are kept rather than deleted, and each now fails fast with a
pointer here if its inputs are gone, so a results-only checkout never fails
obscurely. Cross builds resolve the headers the same way:

```bash
CROSS_COMPILE=aarch64-linux-gnu- BUILD_TESTS_OUT=build/tests-aarch64 ./scripts/build-tests.sh
P0_PREBUILT=1 ./scripts/run-p0-qemu.sh    # skip the cross-compile, reuse build/tests-aarch64
```

### Citations into the driver source

Documents here cite `work/linux/drivers/gpu/arm/midgard/...` as the source of
truth for driver behaviour. Those paths do not resolve in a packaged lab, which
has no kernel tree. The citations still name the right file; recovering the text
means re-fetching and re-integrating the driver, as in "Integration" below.

## Integration

`scripts/build-r54p0-kernel.sh integrate` unpacks the MD5-verified archive resolved
through `configs/r54p0.env` and copies `driver/product/kernel/` into the tree. The
underlying procedure is:

```bash
# MALI_DIR = unpacked archive, MALI_DIR/driver/product/kernel
# KDIR     = kernel source
cp -a "$MALI_DIR"/driver/product/kernel/. "$KDIR/"
cd "$KDIR"
echo 'obj-$(CONFIG_MALI_MIDGARD) += arm/' | tee -a drivers/gpu/Makefile
sed -i '$i source "drivers/gpu/arm/Kconfig"' drivers/video/Kconfig
```

Integration is skipped when `drivers/gpu/arm/midgard/Kbuild` already exists. This is
one-way: the copy also overwrites `include/linux/version_compat_defs.h` and adds
`drivers/base/arm`, `drivers/xen/arm` and `drivers/hwtracing/coresight/mali`, so
re-integrating a tree that carries unrelated local edits destroys them. Start from a
fresh extraction instead.

The driver is built as a **loadable module** (`CONFIG_MALI_MIDGARD=m`, as Arm's
guidelines specify), so `make build` produces both `build/kernel/Image` and
`build/kernel/mali_kbase.ko`. The guest `insmod`s it from `mali-p0-guest` rather than
having Kbase built in.

No local kernel patch is needed on the AArch64 Device Tree route; that pairing builds
and boots unmodified. `kernel/patches/x86/` holds stubs for the x86 Simulated Platform
route, which is not functional — see `kernel/patches/README.md` and
`docs/qemu-x86_64.md`.

## Kernel configuration

The no-Mali device-tree configuration used on AArch64:

```text
CONFIG_MALI_MIDGARD=m
CONFIG_MALI_CSF_SUPPORT=y
CONFIG_MALI_EXPERT=y
CONFIG_MALI_NO_MALI=y
# CONFIG_MALI_REAL_HW is not set
CONFIG_MALI_NO_MALI_DEFAULT_GPU="tKRx"     # G725/G925 no-Mali model
CONFIG_MALI_PLATFORM_NAME="devicetree"
```

`CONFIG_LARGE_PAGE_SUPPORT=y` is selected by default. On x86 the only change is
`CONFIG_MALI_PLATFORM_NAME="vexpress"`, which selects the Simulated Platform Device
instead of Device Tree.

### Configuration order is load-bearing

The fragment is an overlay, **not** a config. The order is:

1. `defconfig` — full baseline
2. append `kernel/config/qemu-aarch64-r54p0.config`
3. `olddefconfig`
4. gate

Reversing 1 and 2 breaks the build. `olddefconfig` assigns every symbol the fragment
does not mention its Kconfig default, so a bare ~20-line fragment yields a near-empty
kernel, and `drivers/gpu/arm/midgard/Kbuild` then aborts with `$(error)` on missing
`CONFIG_DMA_SHARED_BUFFER`, `CONFIG_PM_DEVFREQ` and friends. The failure surfaces
minutes into the build rather than at configure time.

The overlay is content-matched, so re-running `make config` is idempotent instead of
appending another copy of the fragment each time. It cannot be delimited by marker
comments: `olddefconfig` rewrites `.config` and drops comments.

### Gate

Step 4 asserts the symbols the driver hard-requires actually survived step 3, since a
missing one is otherwise a link-time failure after a full build:

```text
CONFIG_MALI_MIDGARD=m          CONFIG_DMA_SHARED_BUFFER=y
CONFIG_MALI_CSF_SUPPORT=y      CONFIG_PM_DEVFREQ=y
CONFIG_MALI_NO_MALI=y          CONFIG_DEVFREQ_THERMAL=y
CONFIG_MALI_EXPERT=y           CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y
CONFIG_MALI_REAL_HW disabled   CONFIG_FW_LOADER=y
CONFIG_MALI_NO_MALI_DEFAULT_GPU="tKRx"
CONFIG_MALI_PLATFORM_NAME="devicetree"
```

The two string symbols must survive verbatim, and `CONFIG_MALI_REAL_HW` must stay off
or the real-hardware backend is built instead of the dummy model.

### Verifying the probe

Verify the driver actually probed, rather than assuming a boot means success. The
healthy no-Mali `insmod` log on AArch64 QEMU `virt` looks like this — the device
prefix is the DT node name, not the literal `mali.0` used in Arm's examples:

```text
mali 6e000000.gpu: Kernel DDK version r54p0-01eac0
mali 6e000000.gpu: Using Dummy Model
mali 6e000000.gpu: GPU metrics tracepoint support enabled
mali 6e000000.gpu: Register LUT 000c0000 initialized for GPU arch 0x000d0801
mali 6e000000.gpu: GPU identified as 0x0 arch 13.8.1 r0p0 status 0
mali 6e000000.gpu: _find_key: OPP table not found (-19)
mali 6e000000.gpu: No OPPs found in device tree! Scaling timeouts using 100000 kHz
mali 6e000000.gpu: No priority control manager is configured
mali 6e000000.gpu: Large page allocation set to true after hardware feature check
mali 6e000000.gpu: No memory group manager is configured
mali 6e000000.gpu: Protected memory allocator not available
mali 6e000000.gpu: No clock(s) available for rate tracing
mali 6e000000.gpu: Clock not available for devfreq
mali 6e000000.gpu: Continuing without devfreq
mali 6e000000.gpu: * MALI kbase_mmap_min_addr compiled to CONFIG_DEFAULT_MMAP_MIN_ADDR, no runtime update possible! *
mali 6e000000.gpu: Probed as mali0
```

Interleaved between those, `Dummy model register access: Writing unsupported
register ...` lines are expected: the dummy model rejects MMU register writes it
does not model, and the probe continues regardless.

The release string is `r54p0-01eac0`, matching `MALI_RELEASE_NAME` in
`drivers/gpu/arm/midgard/Kbuild` and the pinned value in `configs/r54p0.env`.
Some Arm documents print `r54p0-00eac0` in their sample logs; that does not match
the shipped source, so do not assert against it.

`Probed as mali0` is the line that matters. A module can be listed by `lsmod` while
producing no `dmesg` output and being entirely unusable — that happens when the
Device Tree path is selected but no Mali DT node exists to probe against. Absence of
`Using Dummy Model` means the real-hardware backend was built, not the dummy model.
Absence of `Probed as mali0` means `/dev/mali0` will not appear and the P0 tests will
`skip` rather than exercise the driver. The `No OPPs`, `No clock`, `No priority
control manager` and `No memory group manager` lines are warnings about absent
optional DT properties, not probe failures.

Counter values reported by `libGPUCounters` are expected to be `0` under the dummy
model. `Mali GPU device 0 is missing` means the device node could not be opened.

## Version reporting

The loaded driver version is available at runtime:

```bash
cat /sys/module/mali_kbase/version      # e.g. r54p0-01eac0 (UK version 1.36)
```

In the source it is `MALI_RELEASE_NAME` in `drivers/gpu/arm/midgard/Kbuild`. The
U/K interface version (separate from the release name) is `BASE_UK_VERSION_MAJOR`/
`MINOR` in `include/uapi/gpu/arm/midgard/csf/mali_kbase_csf_ioctl.h`; r54p0 declares
`1.36`. This version gates driver capabilities, so it is recorded in test results.
