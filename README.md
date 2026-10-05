# Mali r54p0 QEMU Research Lab

A reproducible research harness for Arm Mali 5th Gen r54p0 Kbase driver work.

## Scope

This repository is designed around the Arm-provided documentation supplied with the
project. It targets the documented No-Mali/dummy-model path for Kbase/driver research,
with QEMU used as the virtual machine environment.

Important limitation: the No-Mali model does not execute real Mali GPU firmware and
does not reproduce all real GPU/MMU/IRQ behavior. Real-hardware validation is a
separate phase.

## Target release

- Mali release: `r54p0-01eac0`
- Published archive MD5: `3bcd3870b58f83442b16b83e432e2f97`
- Default No-Mali GPU model used by the documented 5th-Gen configuration: `tKRx`

Do not commit the Arm source archive, kernel tree, firmware binaries, rootfs images,
or generated build artifacts.

## Quick start

```bash
make bootstrap
# Put the exact Arm r54p0 archive in downloads/ (or configure MALI_ARCHIVE)
make verify
make fetch-kernel
make integrate
make config
make build
make rootfs
make tests
make run
```

## Research priority

P0:
- GPU memory / VMA lifetime
- mmap/cookie lifecycle
- CSF User IO lifecycle
- CSF queue/group teardown
- imported memory

P1:
- KCPU deferred operations
- CQS/fences
- SAME_VA / alias

P2:
- JIT / tiler heap
- real GPU MMU faults
- power transitions

P3:
- firmware static analysis

See `docs/test-matrix.md` and `docs/limitations.md`.

## Guest-side P0 runner

Use `make test-p0-qemu` to boot QEMU, mount the P0 binaries through virtio-9p, run them inside the guest, and collect `results/p0-qemu-results.json`. See `docs/qemu-p0-runner.md`.
