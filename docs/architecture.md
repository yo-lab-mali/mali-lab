# Architecture

```text
userspace
  |
  | /dev/mali0, ioctl, mmap
  v
Kbase (mali_kbase.ko)
  |-- GPU memory / GPU MMU bookkeeping
  |-- mmap / VMA
  |-- CSF queues / CSG / CSI / User IO
  |-- KCPU queues
  |-- CQS / fences
  v
No-Mali dummy model
```

Real CSF firmware and real GPU MMU execution are outside the No-Mali model.

## Setup sequence before any ioctl works

```text
open("/dev/mali0")
  |
  v
KBASE_IOCTL_VERSION_CHECK     negotiate U/K version; no context yet
  |
  v
KBASE_IOCTL_SET_FLAGS         create the Kbase context
  |
  v
MEM_ALLOC / CS_QUEUE_* / ... now usable
```

Kbase holds no API version and no context on a freshly opened file descriptor, so
`kbase_ioctl()` returns `-EPERM` for everything except a short pre-gate list until this
sequence completes. `KBASE_IOCTL_VERSION_CHECK` is declared in the CSF UAPI header, not
the core one. Full detail in `docs/ioctl-gate.md`.

## Address space boundaries

The GPU has its own virtual address space and its own MMU, separate from the CPU's page
tables though structurally similar. Memory must be explicitly mapped through Kbase,
which updates GPU page tables and issues the corresponding MMU and cache operations.

Two address-space notions matter for lifetime work:

- **ASID** — the GPU address space number assigned to a context when work is scheduled.
  This is the identifier used for MMU operations. Each ASID is isolated in hardware, like
  separate Kbase contexts.
- **cookie** — what `MEM_ALLOC` returns to 64-bit userspace in place of a GPU VA, because
  the GPU VA is not known until `mmap()`. See `docs/memory-model.md`.

## Memory classification

The supplied documentation distinguishes three kinds of memory:

| Kind | CPU-mapped | User-accessible | Contents |
|---|---|---|---|
| User Shared | yes | yes | textures, shader programs, job descriptors, render targets, CQS, DMA-bufs, imported user memory, CSF command buffers |
| CSF-only | yes (kernel) | no | memory only the CSF can access, e.g. firmware-reachable command buffers |
| Kbase Shared | temporarily | no | GPU MMU page tables, CSF firmware image, firmware support data |

Kbase can reach anything mapped to the GPU. GPU registers are memory-mapped but do not
live in system RAM, and both Kbase Shared memory and nearly all registers are critical
for GPU operation, so they cannot be mapped into userspace.

## Finding documents

- `docs/abi-check.md` — verified r54p0 ioctl encodings and struct sizes
- `docs/ioctl-gate.md` — the mandatory ioctl handshake
- `docs/memory-model.md` — cookie lifecycle and allocation/free asymmetry
- `docs/csf-model.md` — queue/CSG/User-IO ordering and version gating
- `docs/kcpu-model.md` — deferred execution and the pin/unmap asymmetry
- `docs/synchronization.md` — CQS and fences
- `docs/vma-split-oracle.md` — telling a fixed r54p0 from a vulnerable one
- `docs/limitations.md` — what No-Mali cannot cover
