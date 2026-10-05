# Debugging

Useful kernel configurations:

- KASAN
- KFENCE
- UBSAN
- lockdep
- DEBUG_LIST
- DEBUG_OBJECTS

Use GDB with QEMU's `-s -S` mode for early-boot debugging.

## Sanitizer constraints

Bug bounty eligibility requires reproducing on a conforming configuration, and the
supplied guidelines permit `CONFIG_KASAN*` and `CONFIG_UBSAN*` to be set either way
**except**:

- `CONFIG_KASAN_*_TEST` must be `n`
- `CONFIG_TEST_UBSAN` must be `n`

The self-test variants are excluded. Enabling them to "get more coverage" makes a
finding ineligible. See `docs/build.md`.

## Confirm the driver probed before trusting a result

A module can appear in `lsmod` while being completely unusable. Check for these lines
in dmesg:

```text
mali mali.0: Using Dummy Model                      # dummy backend, not real HW
mali mali.0: GPU identified as 0x0 arch 13.8.1 r0p0 status 0
mali mali.0: Probed as mali0                         # the one that matters
```

If `Probed as mali0` is missing, `/dev/mali0` will not exist and the P0 tests will
report `skip`. A `skip` is not a pass and not evidence about the driver — it means the
environment was not set up. Record which of these lines was observed.

`Clock not available for devfreq` / `Continuing without devfreq` and
`No OPPs found in device tree!` are expected under No-Mali and are not faults.

## Dynamic debug

Several diagnostics are `pr_debug()` and silent by default. To see the VMA-split
protection messages:

```bash
ddcmd 'file drivers/gpu/arm/midgard/mali_kbase_mem_linux.c line 3328-3343 +pt'
```

Line numbers are release-specific; confirm against the integrated source. See
`instrumentation/dynamic-debug/` and `docs/vma-split-oracle.md`.

## Power policy

No-Mali defaults to the `always_on` power policy, unlike a real device's `demand`. This
changes whether the GPU MMU is programmed during alloc/free. Confirm and set explicitly
when a test depends on it:

```bash
cat /sys/class/misc/mali0/device/power_policy   # selected policy in [brackets]
echo always_on    | sudo tee /sys/class/misc/mali0/device/power_policy
echo coarse_demand | sudo tee /sys/class/misc/mali0/device/power_policy
```

## Fence signal timeout

KCPU `FENCE_SIGNAL` has a 10-second timer capped to `MAX_TIMEOUT_MS` (4.5 s). A timeout
is normal progress-preserving behaviour, not automatically a bug. Disable or raise it
during investigation so a timeout is distinguishable from a hang:

```bash
echo 0    | sudo tee /sys/kernel/debug/mali0/fence_signal_timeout_enable
echo <ms> | sudo tee /sys/kernel/debug/mali0/fence_signal_timeout_ms
```

## Reading failure codes

| Code | Meaning here |
|---|---|
| `-EPERM` | ioctl issued before the `VERSION_CHECK`/`SET_FLAGS` handshake completed |
| `-ENOIOCTLCMD` | unrecognised ioctl number — wrong headers or wrong ioctl |
| `-EINVAL` from `SET_FLAGS` | `create_flags` outside `BASEP_CONTEXT_CREATE_KERNEL_FLAGS` |
| `-EINVAL` from `MEM_FREE` | expected when freeing a consumed cookie or SAME_VA memory |
| `-EINVAL` from `mmap` | zero length, non-`MAP_SHARED`, or illegal special handle |

Full detail in `docs/ioctl-gate.md` and `docs/memory-model.md`.
