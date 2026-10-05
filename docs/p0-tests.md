# First runnable P0 tests

These tests exercise the software lifecycle surface identified as P0 in the supplied
Arm documentation: GPU memory allocation, CPU `mmap()`/VMA teardown, and CSF User-IO.
They intentionally stop before real GPU execution or page-fault triggering.

## ABI rule

The tests compile against the **exact integrated r54p0 UAPI headers**. They do not
reconstruct ioctl structures or numbers locally. Set `KERNEL_DIR` to the Linux tree
containing the integrated Arm driver and its `include/uapi` headers.

```bash
export KERNEL_DIR=$PWD/work/linux
make tests
make test-p0
```

A machine without `/dev/mali0` reports the tests as `SKIP` (exit status 77). This is
expected for the host and for a QEMU guest before the No-Mali driver is loaded.

## Mandatory prologue: `VERSION_CHECK` then `SET_FLAGS`

Every test reaches the driver through `mali_open()` (`tests/common/test_common.c`),
which opens `/dev/mali0` **and completes the handshake**. This is not optional
bookkeeping; it is a gate in `kbase_ioctl()`:

```text
open("/dev/mali0")
  -> KBASE_IOCTL_VERSION_CHECK   (nr 52, in the CSF UAPI header)
  -> KBASE_IOCTL_SET_FLAGS       (nr 1,  in the core UAPI header)
  -> every other ioctl is usable
```

Kbase tracks per-file setup state. A freshly opened file descriptor holds no API
version and no Kbase context, so `kbase_ioctl()` reaches
`kbase_file_get_kctx_if_setup_complete()`, gets `NULL`, and returns **`-EPERM`** —
not `-ENOTTY` — for every "normal" ioctl (`MEM_ALLOC`, `CS_QUEUE_*`, ...). Only
`VERSION_CHECK`, `VERSION_CHECK_RESERVED`, `SET_FLAGS`, `GET_GPUPROPS` and the
`KINSTR_PRFCNT_*` calls are dispatched before that check.

Two practical consequences:

- A test that skips the prologue fails with `-EPERM` on every ioctl. That is a
  harness bug, not a driver finding.
- `mali_open()` requests `BASE_UK_VERSION_MAJOR`/`MINOR` and **reads the answer
  back**. Per `kbase_api_handshake()`, when the major matches, the kernel clamps
  `minor` down to its own value, so the driver's reply is authoritative. If the
  negotiated major differs, `mali_open()` refuses the fd and `mali_open_reason()`
  explains why, so the test skips with a real reason instead of misreporting a
  failure.

`KBASE_IOCTL_VERSION_CHECK` lives in `csf/mali_kbase_csf_ioctl.h`, not in the core
header, which makes it easy to miss when reading `mali_kbase_ioctl.h` alone.

## Memory P0

- `memory/001_alloc_free`: allocation -> free.
- `memory/002_alloc_mmap`: allocation -> mmap -> CPU access -> munmap, then assert
  `MEM_FREE` on the consumed cookie is refused with `-EINVAL`.
- `memory/003_mmap_unmap`: map, touch and unmap once, then assert every one of eight
  further `mmap()` attempts with the same cookie is refused with `-EINVAL`.
- `memory/004_free_before_unmap`: map the allocation, then attempt `MEM_FREE` on the
  cookie while the VMA is still mapped.

`MEM_ALLOC` returns a **cookie**, not a GPU VA, on every 64-bit context. Two driver
decisions make that unavoidable rather than flag-dependent: `kbase_create_context()`
sets `KCTX_FORCE_SAME_VA` unconditionally for non-compat callers on a 64-bit build,
and `kbase_kbase_api_mem_alloc()` then adds `flags |= BASE_MEM_SAME_VA` to any
allocation that is neither executable nor fixed/fixable. `kbase_mem_alloc()` binds
the region to a pending cookie and returns
`(cookie + PFN_DOWN(BASE_MEM_COOKIE_BASE)) << PAGE_SHIFT`. That value is the only
valid `mmap()` offset, and a successful mapping *consumes* it:
`kbasep_reg_mmap()` clears `kctx->pending_regions[cookie]` and returns the cookie to
the bitmap.

A consumed cookie is therefore dead in both directions: `kbase_mem_free()` finds no
pending region and returns `-EINVAL`, and `kbase_get_unmapped_area()` finds none and
returns `-EINVAL`. Repeating `mmap`/`munmap` against one cookie is not a legal
lifecycle but a double map of memory the driver has already released, so
`memory/003_mmap_unmap` asserts that it is refused rather than expecting it to work.

So `memory/004_free_before_unmap` asserts the refusal, not the free. `MEM_FREE` on
the consumed cookie returns `-EINVAL`; the test verifies that, then verifies the
still-mapped backing is readable and unmodified, then `munmap()`s it (which is what
actually frees SAME_VA memory). **A `MEM_FREE` that succeeds there would be the
anomaly worth reporting**, because it is the signature of the Project Zero 42451457
"VMA split mishandling" class of issue — a region freed while still mapped into
userspace. See `docs/vma-split-oracle.md`.

## mmap/VMA P0

- `mmap/001_cookie_lifecycle`: map/unmap, then allocate/map again to exercise cookie
  and VMA release/reuse paths.
- `mmap/003_vma_lifecycle`: map, touch, unmap, then assert both the cookie as a
  `MEM_FREE` argument and the cookie as an `mmap()` offset are refused with `-EINVAL`.

Constraints the driver enforces on every `mmap()`: the length must be non-zero and
the mapping must be `MAP_SHARED`, otherwise `kbase_context_mmap()` returns `-EINVAL`.

## CSF User-IO P0

- `user_io/001_queue_bind`: allocate queue backing at a fixed GPU VA, create a CSF
  queue group, register and bind a queue, assert the User-IO handle is non-zero, then
  terminate queue/group and release backing.
- `user_io/002_user_io_map`: bind a queue, mmap the returned User-IO handle for exactly
  `BASEP_QUEUE_NR_MMAP_USER_PAGES` pages, touch the input/output mappings, read them
  back, munmap, then terminate and release the queue.

`CS_QUEUE_REGISTER` needs a **real GPU VA**. `csf_queue_register_internal()` resolves
`buffer_gpu_addr` with `kbase_region_tracker_find_region_enclosing_address()` and
returns `-ENOENT` unless it lands inside a live `KBASE_MEM_TYPE_NATIVE` region. A
cookie is not a region address, and `KBASE_IOCTL_MEM_ALLOC` cannot ask for one —
it has no `fixed_address` field, and its handler `kbase_api_mem_alloc()` is a wrapper
that always sets `fixed_address = 0`.

Both tests therefore allocate through `KBASE_IOCTL_MEM_ALLOC_EX` with `BASE_MEM_FIXED`,
via `p0_alloc_fixed()` in `tests/common/p0_helpers.h`. That suppresses the `SAME_VA`
upgrade, because `kbase_api_mem_alloc_ex()` only adds `BASE_MEM_SAME_VA` when the
allocation is neither GPU-executable nor fixed/fixable, and it takes `gpu_va` from the
request. The two cannot be combined — `kbase_check_alloc_flags()` rejects `SAME_VA`
with `FIXED`/`FIXABLE`.

The requested address is the base of `FIXED_VA_ZONE`, which
`kbase_reg_zone_fixed_va_init()` sets to
`KBASE_REG_ZONE_EXEC_VA_BASE_64 + KBASE_REG_ZONE_EXEC_VA_SIZE` = 2^47 + 4 GiB =
`0x801000000000`, running up to 2^48 for a non-compat 64-bit client. Using the zone
base matters because `kbase_alloc_free_region()` does not range-check `start_pfn`
against the zone, so an out-of-zone address would be accepted and only fail later in
the MMU mapping. Observed `gpu_va` is `0x801000000000`, and the User-IO cookie comes
back as `0x30000`, inside `BASEP_MEM_CSF_USER_IO_PAGES_HANDLE..BASE_MEM_COOKIE_BASE-1`.

Unlike `p0_alloc()`, a `FIXED` region is not `SAME_VA`: there is no cookie, `p0_map()`
does not apply, and `p0_free()` on the returned VA is the release path.

The three-page User-IO mapping and cookie offset follow the documented Kbase mmap path:
page 0 is the GPU hardware doorbell register (writing `0x1` requests start/resume),
page 1 is the Input page (`CS_INSERT_*`, `CS_EXTRACT_INIT_*`), page 2 is the Output
page (`CS_EXTRACT_*`, `CS_ACTIVE`). The tests probe page 0 **read-only** and never
write it, and no queue kick or firmware instruction execution is attempted.

User-IO pages are allocated at `CS_QUEUE_GROUP_CREATE` time only when the negotiated
U/K version is at least `1.35` (`MALI_KBASE_CAP_CSG_CS_USER_PAGE_ALLOCATION`). r54p0
declares `1.36`, so the P0 path is the group-create allocation path. This is asserted
in the ABI check; see `docs/csf-model.md`.

`CS_QUEUE_GROUP_CREATE` also requires `in.padding[]` to be zero —
`check_padding_KBASE_IOCTL_CS_QUEUE_GROUP_CREATE()` returns `-EINVAL` otherwise. The
helpers zero-initialise the union, which satisfies this.

## Why this is safe for No-Mali

These are deterministic lifecycle/regression tests. They do not construct malformed
firmware commands, trigger GPU faults, or attempt a privilege boundary bypass.
No-Mali can therefore cover the Kbase bookkeeping and VMA/object-lifetime portions;
real hardware is still required for faithful GPU MMU IRQ and CSF firmware behavior.
See `docs/limitations.md`.
