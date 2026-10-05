# Test matrix

## P0

| Area | Core question |
|---|---|
| memory/VMA | Does backing outlive all CPU/GPU references? |
| mmap | Are cookies and VMA lifecycle transitions consistent? |
| User IO | Can queue User IO mapping outlive its owner? |
| CSF teardown | Can queue/group state become inconsistent? |
| imports | Do pin/map/unmap/free lifetimes remain valid? |

## P1

| Area | Core question |
|---|---|
| KCPU | Can deferred commands outlive referenced objects? |
| CQS/fences | Do wait/signal dependencies survive teardown? |
| SAME_VA/alias | Are CPU/GPU mappings and lifetimes coherent? |

## P2

JIT/tiler, real MMU faults, power transitions.

## P3

Firmware static analysis.

## P0 status

Eight tests are compiled by `scripts/build-tests.sh` and run by both
`make test-p0` and `make test-p0-qemu`:

| Test | Covers | Guest result |
|---|---|---|
| `memory/001_alloc_free` | alloc -> free without mapping | pass |
| `memory/002_alloc_mmap` | alloc -> mmap -> touch -> munmap, then `MEM_FREE` refused `-EINVAL` | pass |
| `memory/003_mmap_unmap` | one map/unmap, then 8 stale remaps all refused `-EINVAL` | pass |
| `memory/004_free_before_unmap` | `MEM_FREE` refused on a consumed cookie while VMA is live | pass |
| `mmap/001_cookie_lifecycle` | map/unmap then re-allocate to exercise cookie reuse | pass |
| `mmap/003_vma_lifecycle` | stale cookie refused as both `MEM_FREE` and `mmap()` argument | pass |
| `user_io/001_queue_bind` | fixed-VA alloc + register + bind + terminate queue/group | pass |
| `user_io/002_user_io_map` | 3-page User-IO map/touch/read-back/munmap | pass |

The `user_io` pair needs a real GPU VA for `buffer_gpu_addr`, which `MEM_ALLOC` cannot
produce on a 64-bit context — it always returns a cookie, and the ioctl has no
`fixed_address` field. Both allocate with `MEM_ALLOC_EX` + `BASE_MEM_FIXED` at
`FIXED_VA_ZONE` base `0x801000000000` instead. See `docs/p0-tests.md`.

All eight require the `VERSION_CHECK` -> `SET_FLAGS` handshake, which `mali_open()`
performs. See `docs/p0-tests.md` and `docs/ioctl-gate.md`.

## P1 status

P1 sources exist under `tests/kcpu/`, `tests/sync/`, `tests/race/` and `tests/import/`,
but they are **not** built or run. `scripts/build-tests.sh` compiles only the P0 set,
and `make test-p1` currently only prints a reminder. The suites need the same review
the P0 set has had: handshake coverage, ABI validation for the ioctls they use, and
the pin/unmap asymmetry in `docs/kcpu-model.md` reflected in the tests.

`tests/import/` is listed under P0 in this matrix but is likewise not in the compiled
set — sticky-resource map/unmap refcounting and the `UNMAP_IMPORT_FORCE` distinction
between `USER_BUF` and DMA-buf imports are unverified here.
