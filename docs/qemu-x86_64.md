# QEMU x86_64

The supplied Arm material documents a simulated-platform/x86 route that requires
source changes for CONFIG_OF=n, arch timer access, dmb(), and warning cleanup.

This directory is a secondary driver-analysis path. Keep those changes isolated
under `kernel/patches/x86/`.

## Configuration

Identical to the AArch64 target except:

```text
CONFIG_MALI_PLATFORM_NAME="vexpress"
```

That selects the Simulated Platform Device used on Versatile Express, which has no
Device Tree. No driver changes are needed on the Arm/DT path; they are needed here.

## Required patches

Arm supplies `patches_for_virtual_device.zip` targeting **r54p0** specifically. Other
driver versions will need porting.

| Patch | Fixes |
|---|---|
| `0001` | `CONFIG_OF=n`: `of_property_check_flag` conflicting types; version guard `>= v4.15` must become `< v4.1` |
| `0002` | missing `asm/arch_timer.h` |
| `0003` | `arch_timer_get_cntfrq` undefined under `NO_MALI` |
| `0004` | no `dmb()` on non-Arm; substitute `mb()` |
| `0005` | `-Wunused-function` on `pcm_prioritized_process_cb`, `kbasep_devfreq_read_suspend_clock` |
| `0006` | `make clean` fails when arbitration code is absent |

`0002` and `0003` both concern the arch timer interface and are separate patches in the
supplied set.

`0001` note: the guard is inverted in the driver as shipped — it reads `>= v4.15` where
it must read `< v4.1` for `CONFIG_OF=n` builds. Symptom is a conflicting-types error for
`of_property_check_flag` from `version_compat_defs.h`.

`0006` matters because the GPU arbitration reference code is not included. The driver
still builds, but `make clean` fails. Patching is preferred over vendoring the
arbitration code, which is unnecessary when a single guest OS uses the GPU.

## Forcing the simulated platform on a DT machine

Switching `CONFIG_MALI_PLATFORM_NAME` to `vexpress` on a Device Tree system is not
sufficient on its own: the Simulated Platform Device is not compiled in on DT platforms,
so it must be enabled manually, and the remaining DT code paths will fault with a NULL
pointer dereference.

There is no supplied patch for this because the locations differ between driver
versions. Every use of `CONFIG_OF` in the driver must be inverted:

```text
!IS_ENABLED(CONFIG_OF)      -> 1
 IS_ENABLED(CONFIG_OF)      -> 0
#ifndef  CONFIG_OF          -> #if 1
#ifdef   CONFIG_OF          -> #if 0
#if !defined(CONFIG_OF)     -> #if 1
#if  defined(CONFIG_OF)     -> #if 0
of_match_ptr(kbase_dt_ids) -> NULL
```

## Status in this repository

`kernel/patches/x86/` holds five stub files and no real patch content. Arm ships six
patches in `patches_for_virtual_device.zip` targeting r54p0, and the numbering here
does not line up because Arm's arch-timer work was split into two files here.
`kernel/patches/README.md` has the full mapping.

This path is not functional. `scripts/apply-patches.sh` applies nothing by design,
and the x86 kernel config fragments exist but describe a build that has never been
attempted. Integration itself is no longer the blocker — `make integrate` performs
the real DDK copy for any target — so the gap is entirely the missing patch content.

Treat x86 as unimplemented until the real patches are vendored from
`patches_for_virtual_device.zip` and verified against the selected kernel/r54p0 pair.
The AArch64 DT path in `docs/qemu-aarch64.md` is the supported route.
