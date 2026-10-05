# Memory model

Model each allocation as a lifecycle graph:

```text
allocation
  -> GPU VA / mapping
  -> CPU mmap / VMA
  -> optional import/alias
  -> GPU/queue reference
  -> unmap
  -> unpin/free
```

Primary invariant:

> Any live CPU VMA, GPU mapping, imported backing reference or asynchronous
> command reference must keep the underlying state valid for as long as required.

The test suite is intentionally lifecycle-oriented rather than malformed-input-only.

## Allocations return a cookie, not a GPU address

This is the detail that makes cookie handling the interesting attack surface, so it is
worth stating precisely.

For a 64-bit userspace process, `KBASE_IOCTL_MEM_ALLOC` does **not** return a GPU
virtual address. It returns a *cookie*. `kbase_mem_alloc()` allocates the region, binds
it to a free slot in `kctx->pending_regions[]`, clears the bit in the `kctx->cookies`
bitmap, and returns:

```text
(cookie_nr + PFN_DOWN(BASE_MEM_COOKIE_BASE)) << PAGE_SHIFT
```

The same two-step shape applies to `MEM_ALLOC_EX`, `MEM_ALIAS` and `MEM_IMPORT`. The
GPU virtual address is not known until `mmap()` is called, which is why the cookie is
what userspace holds in the interim.

The mapping then consumes the cookie. `kbasep_reg_mmap()` takes the pending region,
sets `kctx->pending_regions[cookie] = NULL` and returns the slot to the bitmap. After
that, the cookie value is stale: `kbase_mem_free()` can no longer resolve it and
returns `-EINVAL`, and `kbase_get_unmapped_area()` finds no pending region for it and
returns `-EINVAL` as well. A consumed cookie is dead in both directions.

The cookie is not a consequence of which flags userspace passes. Two driver decisions
force it for every non-compat caller on a 64-bit build:

1. `kbase_create_context()` sets `KCTX_FORCE_SAME_VA` unconditionally when the caller
   is not `KCTX_COMPAT`.
2. `kbase_kbase_api_mem_alloc()` then adds `flags |= BASE_MEM_SAME_VA` to any
   allocation that is neither executable nor fixed/fixable.

The practical consequence is that **no `KBASE_IOCTL_MEM_ALLOC` can be turned into a
real GPU VA from userspace**. That ioctl has no `fixed_address` field at all, and its
handler `kbase_api_mem_alloc()` is a wrapper around `kbase_api_mem_alloc_ex()` that
always sets `fixed_address = 0`. So any ioctl that resolves a region by real GPU
address is unreachable through the plain-alloc path. The concrete case here is
`CS_QUEUE_REGISTER`: `csf_queue_register_internal()` calls
`kbase_region_tracker_find_region_enclosing_address()` and returns `-ENOENT` unless the
address lands inside a live `KBASE_MEM_TYPE_NATIVE` region, and a cookie is not a
region address.

`KBASE_IOCTL_MEM_ALLOC_EX` does break out of this. Requesting `BASE_MEM_FIXED` with a
page-aligned `fixed_address` suppresses the `SAME_VA` upgrade — `kbase_api_mem_alloc_ex()`
only adds `BASE_MEM_SAME_VA` when the allocation is neither GPU-executable nor
fixed/fixable — and it returns the requested VA verbatim. `kbase_check_alloc_flags()`
rejects `SAME_VA` together with `FIXED`/`FIXABLE`, so the two never combine. The
address must be in `FIXED_VA_ZONE` (`0x801000000000` .. 2^48 for a non-compat 64-bit
client); `kbase_alloc_free_region()` does not range-check it, so an out-of-zone
request is accepted by the kernel and fails later. `p0_alloc_fixed()` in
`tests/common/p0_helpers.h` uses the zone base. A `FIXED` region is not `SAME_VA`, so
it has no cookie and is released with `MEM_FREE` on its VA. See `docs/p0-tests.md`.

So there are two distinct notions of "the same allocation handle", and conflating them
is the whole bug class:

| Phase | Valid operations |
|---|---|
| after `MEM_ALLOC`, before `mmap` | `mmap(cookie)`, or `MEM_FREE(cookie)` |
| while the VMA is live | further `mmap` by region PFN, `munmap` |
| after `munmap` | `munmap` only; `MEM_FREE(cookie)` and `mmap(cookie)` are `-EINVAL` |

`mmap()` is restricted: non-zero length and `MAP_SHARED` are both mandatory, otherwise
`kbase_context_mmap()` returns `-EINVAL`. `MAP_PRIVATE` is rejected because the
underlying region is shared with the GPU.

## Address space layout

The cookie range is one of several special-handle windows the `mmap()` offset can
select. `kbase_context_mmap()` switches on `vma->vm_pgoff`:

```text
BASEP_MEM_INVALID_HANDLE / BASEP_MEM_WRITE_ALLOC_PAGES_HANDLE   -> -EINVAL (illegal)
BASE_MEM_MMU_DUMP_HANDLE                                        -> MMU dump (vector dump builds only)
BASEP_MEM_CSF_USER_REG_PAGE_HANDLE                              -> single read-only HW page
BASEP_MEM_CSF_USER_IO_PAGES_HANDLE .. BASE_MEM_COOKIE_BASE-1   -> CSF User-IO pages
BASE_MEM_COOKIE_BASE .. BASE_MEM_FIRST_FREE_ADDRESS-1          -> SAME_VA cookie region
otherwise                                                       -> existing GPU VA / PFN
```

The `BASEP_MEM_WRITE_ALLOC_PAGES_HANDLE` case matters for aliasing: it is the only way
to request special mapping behaviour via `MEM_ALIAS`.

SAME_VA static zones start at `1<<47` for 64-bit userspace (`1<<43`–`1<<44` for 32-bit)
for `BASE_MEM_FIXED` / `BASE_MEM_FIXABLE`. `CUSTOM_VA` is the dynamic zone used for
Kbase-driven JIT allocations.

## Freeing

Freeing is not symmetric with allocation, and the rejection paths are deliberate:

- `MEM_FREE` on a cookie that has already been mapped is `-EINVAL` (cookie consumed).
- `MEM_FREE` on a real GPU VA in the SAME_VA zone is `-EINVAL` with
  `called on SAME_VA memory` — SAME_VA memory is freed via `munmap()`.
- `MEM_FREE` on a region flagged `BASEP_MEM_NO_USER_FREE` is `-EINVAL` with
  `Attempt to free GPU memory whose freeing by user space is forbidden!`. This is the
  flag Kbase sets on queue buffers and tiler-heap backing, precisely so userspace
  cannot free memory the driver still owns.

## No-Mali consequence

Under No-Mali the default power policy is `always_on`, unlike a real device which uses
`demand`. That matters for memory testing: the GPU MMU is only programmed when the GPU
is powered. The policy is switchable at runtime via
`/sys/class/misc/mali0/device/power_policy` (`always_on`, `coarse_demand`, ...), and
the current selection is shown in brackets when you `cat` that file.

`BASE_MEM_GROW_ON_GPF` cannot be meaningfully exercised here. Growing on GPU page
fault requires a real GPU MMU IRQ, which a virtual platform never raises; Arm's own
guidance is that Kbase must be patched to trigger the IRQ manually and populate the
MMU status registers. Do not add the flag and conclude No-Mali covered page faults.
See `docs/limitations.md`.

Also note that when Kbase cannot handle a GPU page fault it terminates **all** CSGs on
the faulting context, so any growth-related test would be observing group teardown,
not growth.
