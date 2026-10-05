# Limitations

1. No-Mali is a software/dummy model.
2. It does not execute real Mali firmware.
3. Dummy register operations do not emulate all hardware side effects.
4. GPU MMU IRQ/page-fault behavior is not faithfully reproduced.
5. The Arm virtual-platform Device Tree examples are not proof that stock QEMU
   implements those Mali MMIO/IRQ semantics.
6. Real GPU, power-management, firmware-execution and hardware-fault findings
   require an appropriate real platform or explicit hardware model.

Do not interpret a No-Mali result as proof of a hardware-only vulnerability.

## Stated more precisely

The dummy model replaces GPU IRQ handlers and register accesses with dummy accesses to
a simple model. Every operation completes instantaneously and does not emulate effects
on the rest of the system. A vulnerability that requires the GPU or GPU firmware to
perform reads, writes or instruction execution cannot be tested here at all.

Consequences for specific surfaces:

- **GPU page faults.** Nothing raises a GPU MMU IRQ on a virtual platform. Arm's own
  guidance is to use a real GPU to trigger the IRQ, or to modify Kbase to trigger it
  manually and populate the MMU status registers. `BASE_MEM_GROW_ON_GPF` therefore
  cannot be meaningfully exercised. Do not add the flag and conclude No-Mali covered
  growth — an unhandled fault terminates all CSGs on the faulting context, so the
  observation would be group teardown, not growth.
- **Firmware instructions.** `SYNC_WAIT`, `SYNC_SET`, `SYNC_ALL` and the rest of the CSF
  instruction set are never executed, so fence/CQS combinations that depend on the
  GPU-side instruction cannot be validated. The KCPU-side command pairs can be.
- **Power state.** No-Mali defaults to `always_on`, where a real device uses `demand`.
  MMU programming during alloc/free depends on power state, so power-transition
  behaviour is not exercised.
- **Counters.** `libGPUCounters` reports `0` for all counters under the dummy model.
  A zero counter reading is not a malfunction.
- **No GPU MMU dump.** `BASE_MEM_MMU_DUMP_HANDLE` requires `CONFIG_MALI_VECTOR_DUMP`
  and is not available in production builds.
- **Decoding firmware requires breaking the driver.** Compiling the firmware parser into
  a No-Mali build makes driver startup fail by design. That is a decoding aid, not a
  working configuration, and any crash there is not a finding. See `docs/firmware.md`.

## What No-Mali does cover

Kbase bookkeeping, object and VMA lifetime, cookie lifecycle, CSF queue/CSG teardown
ordering, ioctl validation and padding checks, import pin/unmap refcounting, and
KCPU command ordering. These are the P0/P1 surfaces in `docs/test-matrix.md`.

## Reporting

A No-Mali result is a driver-side observation on a modelled backend. Report it against
the driver, not the hardware, and reproduce on a conforming configuration before
treating it as a hardware finding. `docs/findings.md` records the required metadata.
