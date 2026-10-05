# Findings

Record only reproducible observations here.

Suggested format:

- TEST:
- r54p0 release:
- kernel:
- platform:
- backend:
- sanitizer:
- expected:
- observed:
- dmesg:
- reproducer:
- assessment:

Do not label a No-Mali observation as a hardware vulnerability without real-platform
validation.

## Additional fields worth recording

The template above is the minimum. These fields decide whether a finding is usable,
and several are easy to lose:

- **U/K version negotiated:** the value returned by `KBASE_IOCTL_VERSION_CHECK`, not
  the one requested. Driver capabilities are gated on the negotiated value, so a result
  is not reproducible without it. See `docs/ioctl-gate.md`.
- **Config conformance:** whether the reproducing kernel matches the permitted
  deviations in `docs/build.md`. `CONFIG_KASAN_*_TEST` and `CONFIG_TEST_UBSAN` must be
  `n`.
- **Power policy:** `always_on` or other, read from
  `/sys/class/misc/mali0/device/power_policy`. No-Mali defaults to `always_on`; MMU
  programming during alloc/free depends on it.
- **Driver probe confirmation:** whether `Probed as mali0` appeared in dmesg. Without
  it `/dev/mali0` does not exist and any `skip` is an environment problem, not a result.
- **Dynamic debug state:** whether dynamic debug was enabled, and for which lines. Many
  diagnostics are `pr_debug()` and silent otherwise, so their absence is not evidence.
- **Skip vs pass:** a `skip` (exit 77) means the test did not run. It must never be
  recorded as a pass.

## Assessment vocabulary

Prefer describing what was observed and which invariant it touched, over asserting a
vulnerability. Useful distinctions:

- **Lifetime invariant violated** — backing became invalid while a live reference
  existed. Name the reference type (VMA, GPU mapping, import refcount, async command).
- **Rejected as designed** — the driver returned `-EINVAL`/`-EPERM` on an operation the
  ABI forbids. This is a pass, not a near-miss. See `docs/memory-model.md` for the
  cases where rejection is the correct outcome, including `memory/004_free_before_unmap`.
- **Not covered by No-Mali** — requires GPU MMU IRQ or firmware execution. Route to
  real hardware. See `docs/limitations.md`.

## Before writing a finding

- The test must have actually run; confirm the status was `pass`, not `skip`.
- The reproduction must hold on a configuration conforming to `docs/build.md`.
- State explicitly whether the observation is driver-side or firmware/hardware. The
  dummy model covers only the former.
