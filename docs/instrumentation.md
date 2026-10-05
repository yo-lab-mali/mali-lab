# Instrumentation

Recommended layers:

1. dynamic_debug for Kbase source
2. object lifetime logging
3. KASAN/KFENCE
4. lockdep
5. QEMU/GDB when needed

Keep logs reproducible and attach metadata to every result.

## Eligibility note

If a sanitizer is enabled, `CONFIG_KASAN_*_TEST` and `CONFIG_TEST_UBSAN` must be `n` for
the result to be reproducible on a conforming configuration. See `docs/build.md` and
`docs/debugging.md`.

## dynamic_debug

Many Kbase diagnostics are `pr_debug()` and produce nothing by default. Absence of a
message therefore proves nothing until dynamic debug is confirmed on.

```bash
# single file/line range (r54p0 line numbers; confirm against integrated source)
ddcmd 'file drivers/gpu/arm/midgard/mali_kbase_mem_linux.c line 3328-3343 +pt'

# discover sites without hardcoding lines
grep -i unexpected /sys/kernel/debug/dynamic_debug/control | grep -i pages
```

Scripts: `instrumentation/dynamic-debug/enable-all.sh`, `enable-csf.sh`,
`enable-kcpu.sh`.

The VMA-split protection messages are the main use for this layer; see
`docs/vma-split-oracle.md`.

## Confirming the driver probed

Instrumentation is only meaningful once Kbase is actually loaded and probed. Capture
these from dmesg before interpreting anything else:

```text
mali mali.0: Using Dummy Model
mali mali.0: GPU identified as 0x0 arch 13.8.1 r0p0 status 0
mali mali.0: Probed as mali0
```

`Probed as mali0` missing means no `/dev/mali0`, and any test `skip` is an environment
failure rather than a driver result.

## Environment state to capture

Attach to every result, since these change behaviour rather than just verbosity:

- negotiated U/K version (from `KBASE_IOCTL_VERSION_CHECK` reply)
- power policy (`/sys/class/misc/mali0/device/power_policy`)
- driver release (`/sys/module/mali_kbase/version`)
- whether dynamic debug was enabled, and for which sites
- sanitizer configuration actually built in

Reporting: `harness/reporting/` (`make-report.sh`, `collect-dmesg.sh`,
`collect-kasan.sh`, `collect-lockdep.sh`). Debugfs snapshots via
`instrumentation/debugfs/`.

## QEMU and GDB

`-s -S` for early-boot debugging. Useful when the driver fails to probe: it allows
inspection before the kernel is released, which is easier than catching a later fault.
