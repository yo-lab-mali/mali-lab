# Synchronization

Model synchronization as:

```text
GPU Queue <-> CQS <-> KCPU Queue <-> userspace
                       |
                     Fence
                       |
                  other context
```

Focus on lifetime, ordering, cleanup and blocked waiters.

## Two mechanisms, different scopes

**CQS objects** synchronize within a single context, between GPU queues, KCPU queues,
and the userspace client of that context. **Fences** synchronize between different
contexts/processes, passed by file descriptor.

There is **no cross-process synchronization via CQS**. Userspace can only signal or
wait on CQS objects in its own context. A test that expects a CQS wait to be satisfied
by another process is testing an impossibility; the result is a permanent block, not
a race.

Fences require `CONFIG_SYNC_FILE` (default on recent Android, via `CONFIG_DRM`).

## CQS object layout

A CQS object is a pair of values in memory:

- a 32-bit (`Sync32`) or 64-bit (`Sync64`) unsigned value
- a 32-bit error value

GPU queues and KCPU queues use the identical format, which is also exposed to
userspace. That shared format is what lets any of the three signal or wait on any
other.

Memory is allocated with the `BASE_MEM_CSF_EVENT` flag and is **permanently mapped
into the kernel for its whole lifetime** using `vmap()`, so Kbase can read and update
it without a fault. Any test that unmaps or frees `BASE_MEM_CSF_EVENT` memory is
fighting a `vmap()` that will not go away.

Alignment when suballocating from `BASE_MEM_CSF_EVENT`:

| Object | Alignment |
|---|---|
| `Sync32` | 8 bytes |
| `Sync64` | 16 bytes |

Misaligning a suballocated CQS object is a real correctness bug that will not
necessarily surface as an obvious crash.

Mapping is CPU-and-GPU uncached, except on Ace-Lite systems where it is CPU-and-GPU
cached and outer-sharable.

## Combining fences with CQS

Signalling a fence on GPU completion combines a KCPU `FENCE_WAIT` with a
`CQS_SET`/`CQS_SET_OPERATION`, plus a corresponding `SYNC_WAIT` CSF firmware
instruction on the GPU queue.

Signalling a fence from a GPU queue runs in the opposite direction: a `SYNC_SET` CSF
firmware instruction first, then a KCPU `CQS_WAIT`/`CQS_WAIT_OPERATION` followed by a
KCPU `FENCE_SIGNAL`.

Neither combination is fully exercisable under No-Mali, since the GPU-side
`SYNC_WAIT`/`SYNC_SET` firmware instructions are not executed. See
`docs/limitations.md`.

## Blocked waiters

A KCPU queue blocks on CQS objects, fences, or JIT allocations. While blocked it makes
no progress, though further commands may still be enqueued up to the 256-command
limit. Some commands take immediate action on enqueue even while blocked — notably
`MAP_IMPORT`, which pins regardless of earlier blocking commands.

The cleanup question that matters for lifetime testing: `KCPU_QUEUE_DELETE` drains any
remaining blocked commands and unblocks dependent synchronization objects. Whether
draining means *executing* or *discarding* them is the difference between a lifetime
bug and correct cleanup, so it is worth testing directly rather than assuming.

`CS_EVENT_SIGNAL` signals a CQS object from userspace to notify Kbase or the GPU.
`STREAM_CREATE` exists for `base_fence` objects, but the `stream_fd` member is ignored
in KCPU fence commands, so it is not required for that path.
