# CSF model

Documented high-level sequence:

```text
CS_QUEUE_REGISTER
  -> CS_QUEUE_GROUP_CREATE
  -> CS_QUEUE_BIND
  -> mmap(User IO)
  -> CS_QUEUE_KICK
  -> terminate/cleanup
```

Treat Queue, CSG/CSI, User IO pages, VMA and Context as an object graph.
The most valuable tests exercise unusual but ABI-valid teardown ordering.

## Ordering is not free

The order above matters, and the driver's own teardown comments enumerate the states a
queue can be left in:

- `CS_QUEUE_REGISTER` requires a valid GPU VA with a power-of-2 size between
  `CS_RING_BUFFER_MIN_SIZE` and `CS_RING_BUFFER_MAX_SIZE`. It leaves the queue
  **unbound** and marks the backing region `BASEP_MEM_NO_USER_FREE`, so userspace
  cannot free the ring buffer out from under the queue.
- `CS_QUEUE_GROUP_CREATE` must precede `CS_QUEUE_BIND`. `CS_QUEUE_BIND` sets up the
  Command Stream Interfaces and validates `csi_index` against collisions in the group.
- `CS_QUEUE_BIND` is **two-stage**. It returns a temporary cookie; the second stage is
  the `mmap()` of the User-IO pages. A bind that is never completed by that `mmap()`
  leaves the queue in a half-bound state.

Per `unbind_queue()`, the driver explicitly handles a queue terminated *after*
`CS_QUEUE_BIND` but *before* the second-stage `mmap()`. That path is a legitimate
teardown ordering and a good regression target, not a misuse.

## User-IO pages

Each bound queue exposes exactly `BASEP_QUEUE_NR_MMAP_USER_PAGES` (3) pages:

| Page | Contents |
|---|---|
| 0 | GPU hardware register-mapped doorbell; write `0x1` to request start/resume |
| 1 | Input: `CS_INSERT_*` and `CS_EXTRACT_INIT_*` virtual registers |
| 2 | Output: `CS_EXTRACT_*` virtual registers and `CS_ACTIVE` |

`CS_ACTIVE` determines whether the queue can be started via the doorbell, or whether
`CS_QUEUE_KICK` must be used instead.

The Input and Output pages are also mapped into the kernel so Kbase can inspect them
for scheduling, and for suspend/resume of GPU work. `CS_INSERT_*`/`CS_EXTRACT_*` are
offsets into the queue's ring buffer modulo its size, which is what makes the buffer a
ring buffer.

Because GPU hardware doorbell registers are a scarce resource, Kbase remaps a queue's
doorbell page to a shared `dummy_db_page` whenever the queue is stopped on hardware or
the GPU is powered down. Writes to that page are discarded, and on power-up Kbase
signals the firmware to restart the queues itself. So a doorbell write is not
guaranteed to have taken effect by the time the userspace call returns.

## Version gating

User-IO page allocation happens at `CS_QUEUE_GROUP_CREATE` time only when the
*negotiated* U/K version is at least `1.35`
(`MALI_KBASE_CAP_CSG_CS_USER_PAGE_ALLOCATION`, `required_major/minor = 1/35`).
Below that, pages are allocated at bind time instead. The two allocations have
different lifetimes relative to the group, so a test that mixes a low negotiated
version with group-creation assumptions is testing the wrong thing.

r54p0 declares `BASE_UK_VERSION_MAJOR`/`MINOR` = `1.36`. The negotiated value is the
minimum of what userspace requested and what the driver supports, and it is per-file
state established by `KBASE_IOCTL_VERSION_CHECK`. See `docs/p0-tests.md`.

`CS_QUEUE_GROUP_CREATE` also requires `in.padding[]` to be zero, otherwise
`check_padding_KBASE_IOCTL_CS_QUEUE_GROUP_CREATE()` rejects the call with `-EINVAL`.

## Group limits

A group holds between `BASEP_GPU_QUEUE_PER_QUEUE_GROUP_MIN` (8) and
`BASEP_GPU_QUEUE_PER_QUEUE_GROUP_MAX` (32) queues. These are compile-time constants,
not runtime-reported limits; `CS_GET_GLB_IFACE` reports runtime maxima for group and
stream counts via a two-step size query.

`CS_QUEUE_GROUP_CREATE` may allocate DVS buffers on capable GPUs. Userspace retains
ownership of the DVS buffer and must manage it separately after
`CS_QUEUE_GROUP_TERMINATE`.

## Fanout

`KBASE_IOCTL_QUEUE_GROUP_CLEAR_FAULTS` takes an array of queue buffer addresses. It
exists because each queue can report only **one** error at a time via `read()`; a
second fault is not reported until the first is cleared.
