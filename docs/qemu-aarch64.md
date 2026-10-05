# QEMU AArch64

This is the primary virtual-machine target.

The Device Tree configuration follows the Arm virtual-platform example conceptually,
but stock QEMU is not assumed to emulate Mali hardware.

The No-Mali model is therefore the backend of interest.

## Device Tree node

The documented no-Mali node to inject into the guest DTB:

```text
gpu: gpu@6e000000 {
        compatible = "arm,mali-midgard";
        reg = <0x0 0x6e000000 0x0 0x200000>;
        interrupts = <0 168 4>, <0 168 4>, <0 168 4>;
        interrupt-names = "JOB", "MMU", "GPU";
};
```

`compatible` must be `arm,mali-midgard` for `CONFIG_MALI_PLATFORM_NAME="devicetree"`.
The three interrupts are `JOB`, `MMU`, `GPU` in that order.

Boot with `acpi=off` and the custom blob via `-dtb`.

## Build the DTB

`qemu/aarch64/dt/mali-no-mali.dtsi` holds the node. It is not a standalone blob:
merge it into a machine-specific QEMU `virt` DTB, because the addresses and
interrupts above are only meaningful if the guest actually provides those resources.

`qemu/aarch64/dumpdtb.sh` does that merge. It asks QEMU for its own `virt` DTB,
decompiles it with `dtc`, splices the `gpu@6e000000` node in as a root child, and
recompiles:

```bash
./qemu/aarch64/dumpdtb.sh
export QEMU_DTB="$PWD/build/dtb/virt-mali.dtb"
```

The node must be inserted *after* the root's own properties and *before* its first
child; `dtc` rejects a tree where properties follow subnodes. The script re-reads
the rebuilt blob and fails if `arm,mali-midgard` is absent, so a silently useless DTB
cannot reach a boot.

`scripts/run-p0-qemu.sh` picks the result up through its `QEMU_DTB` hook, and
`qemu/aarch64/run.sh` (what `make run` calls) defaults `QEMU_DTB` to
`build/dtb/virt-mali.dtb`. Both warn loudly and boot anyway if the blob is missing.
Passing no `-dtb` at all is the probe trap below.

## Boot and run

```bash
make rootfs                                    # build/rootfs/rootfs.ext4
make dtb                                       # build/dtb/virt-mali.dtb
QEMU_DTB="$PWD/build/dtb/virt-mali.dtb" ./scripts/run-p0-qemu.sh
```

or, equivalently, `make all` builds all three and prints the runner command.

`build-rootfs.sh` stages an Ubuntu base arm64 userspace plus `busybox-static`,
overlays `rootfs/overlay/`, installs `build/kernel/mali_kbase.ko` into `/lib/modules/`
and writes a raw ext4 image with `mke2fs -d` — no loop mount and no root required.
Both downloads are pinned by SHA256 in the script. `busybox-static` is not optional:
ubuntu-base ships neither `insmod` nor `poweroff`, and the runner is PID 1, so without
a working `poweroff` the boot ends in a kernel panic instead of a clean shutdown.

The guest runs `init=/usr/local/bin/mali-p0-guest`, which is PID 1, so nothing has
mounted `/proc` or `/sys` and no module has been loaded when it starts. Its preamble
does both — mounts, then `insmod /lib/modules/mali_kbase.ko` — and every step is
non-fatal, so a driver that fails to load degrades the run to recorded `skip`s rather
than a panic. Loading is still not probing; see below.

## The probe trap

On a Device Tree platform with no Mali DT node, the module still appears in `lsmod` but
produces **no dmesg output and Kbase is unusable** — there is nothing to probe against.
`/dev/mali0` will not exist and the P0 tests will report `skip`.

Verify `Probed as mali0` appears before drawing any conclusion from a skip. See
`docs/build.md` and `docs/debugging.md`.

## What this target does and does not prove

QEMU does not emulate Mali hardware. The DT node makes Kbase probe a dummy GPU so the
driver's own bookkeeping can be exercised. It does not provide GPU MMU semantics, IRQs
or firmware execution. See `docs/limitations.md`.
