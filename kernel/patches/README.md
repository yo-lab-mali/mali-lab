# Kernel patches

The AArch64 Device Tree route needs **none**. The selected pairing — Linux 6.6.158
with r54p0-01eac0, driver as a loadable module — builds and boots unmodified, and
that is the route `scripts/build-r54p0-kernel.sh` implements. The Mali device tree
node lives in `qemu/aarch64/dt/mali-no-mali.dtsi` and is applied by
`qemu/aarch64/dumpdtb.sh`, not by patching the kernel.

The x86 Simulated Platform route does need patches, and those are kept as
placeholders. Do not apply them blindly: the supplied Arm material documents
changes to `CONFIG_OF`, the arch timer, `dmb()` and warning cleanup, which belong
under `x86/`.

## x86 inventory does not match Arm's numbering

Arm supplies `patches_for_virtual_device.zip` with **six** patches targeting
**r54p0 specifically**. This directory has five, and the numbers do not line up
because Arm splits the arch-timer work into two separate patches that were
merged into one here. Do not assume a filename number is Arm's patch number.

| Arm patch | Fixes | File here |
|---:|---|---|
| `0001` | `CONFIG_OF=n`: `of_property_check_flag` conflicting types; version guard `>= v4.15` must be `< v4.1` | `0001-config-of.patch` |
| `0002` | missing `asm/arch_timer.h` | `0002-arch-timer.patch` |
| `0003` | `arch_timer_get_cntfrq` undefined under `NO_MALI` | `0002-arch-timer.patch` |
| `0004` | no `dmb()` on non-Arm; substitute `mb()` | `0003-dmb.patch` |
| `0005` | `-Wunused-function` on `pcm_prioritized_process_cb`, `kbasep_devfreq_read_suspend_clock` | `0004-warning-cleanup.patch` |
| `0006` | `make clean` fails when arbitration code is absent | `0005-make-clean.patch` |

Every file here is a two-line stub except `0005-make-clean.patch`, which carries
its rationale. `scripts/apply-patches.sh` applies nothing, by design: the x86 route is
not functional until the real patches are vendored from the zip and verified against
the selected kernel/r54p0 pair.

The AArch64 Device Tree path needs none of these and is the supported route. See
`docs/qemu-x86_64.md`.
