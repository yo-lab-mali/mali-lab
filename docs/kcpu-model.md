# KCPU model

KCPU queues execute kernel-side CPU commands asynchronously.

Relevant documented command classes include:

- FENCE_WAIT / FENCE_SIGNAL
- CQS_WAIT / CQS_SET
- CQS_WAIT_OPERATION / CQS_SET_OPERATION
- ERROR_BARRIER
- MAP_IMPORT / UNMAP_IMPORT / UNMAP_IMPORT_FORCE
- JIT_ALLOC / JIT_FREE

Research focus: deferred execution versus object destruction.

## Limits

- Up to **256** KCPU queues per context.
- Up to **256** active commands per queue.
- Queues execute strictly in order, independent of other KCPU queues unless explicitly
  synchronized.
- Up to **32** CQS wait conditions per `CQS_WAIT` command.
- Commands are submitted **one at a time** via `KCPU_QUEUE_ENQUEUE`.

A blocked queue makes no progress on later commands, but more commands may still be
enqueued up to the limit. That is the mechanism behind the deferred-execution hazard:
commands past a blocking one sit queued against objects that may be torn down
underneath them.

## The pin/unmap asymmetry is the hazard

This is the specific asymmetry that makes "deferred execution versus object
destruction" a real attack surface rather than a slogan:

| Command | Timing | Pin state |
|---|---|---|
| `MAP_IMPORT` | pins **immediately on enqueue**, even when the queue is blocked by earlier commands | pinned |
| `UNMAP_IMPORT` | decrements the user-mapping refcount; cache ops and GPU MMU teardown happen when the count reaches zero | **still pinned** |
| `UNMAP_IMPORT_FORCE` | forces the refcount to zero for `USER_BUF` imports | still pinned |

So `UNMAP_IMPORT` reaching zero does **not** unpin. Memory stays pinned until the
imported region is removed with `MEM_FREE`. Any test that treats "unmapped" as
"unpinned" is modelling the wrong lifetime, and a destroy-on-unmap assumption would
produce a use-after-unpin rather than testing the real behaviour.

`UNMAP_IMPORT_FORCE` applies only to `USER_BUF` imports. DMA-buf imports maintain a
separate refcount and are not unmapped this way — so the force path has different
semantics for the two import kinds, and a test covering only one is not covering the
force command.

`STICKY_RESOURCE_MAP`/`UNMAP` mirror this refcounting at the ioctl layer: map
increments the user mapping refcount and pins if needed; unmap decrements but does not
unpin. The first reference also triggers cache coherency, and the last one performs
cache coherency and GPU MMU teardown.

## JIT allocation

`JIT_ALLOC` writes the resulting addresses into **GPU data structures, not through the
original command parameter struct**, so the caller cannot read the addresses back out
of the command. Allocation may be delayed to enforce in-flight JIT limits, and that
delay blocks subsequent commands on the same queue.

`JIT_FREE` identifies regions by an id allocated by userspace, **not by GPU address**.
Freeing by address is not the supported path.

## Fence signal timeout

`BASE_KCPU_COMMAND_TYPE_FENCE_SIGNAL` has a 10-second timer defined by
`KCPU_FENCE_SIGNAL_TIMEOUT_CYCLES`, capped to `MAX_TIMEOUT_MS` (4.5 seconds). The cap
is what actually applies.

The timeout exists so progress is possible even when a dependency blocks
indefinitely — which means a timeout firing is normal driver behaviour, not
necessarily a bug. Distinguishing the two requires the timeout itself to be disabled
during the run:

```bash
# disable entirely (0)
echo 0 | sudo tee /sys/kernel/debug/mali0/fence_signal_timeout_enable
# or raise it, up to MAX_TIMEOUT_MS
echo <ms> | sudo tee /sys/kernel/debug/mali0/fence_signal_timeout_ms
```

When a fence-signal timeout fires, Kbase asks userspace to dump its CPU queues via
`BASE_CSF_NOTIFICATION_CPU_QUEUE_DUMP`, answered with `KBASE_IOCTL_CS_CPU_QUEUE_DUMP`.
Kbase captures that string verbatim and never parses it; it is discarded if sent at
an unintended time. A dump arriving unexpectedly is therefore not evidence of a fault.

## Error propagation

A KCPU queue can carry an error condition that optionally propagates from CQS objects
or fences to other CQS objects. `ERROR_BARRIER` clears the queue's error condition and
runs only after prior blocking operations complete; errors can propagate to CQS
objects right up until that point. `CQS_SET` and `CQS_SET_OPERATION` **always**
propagate queue errors, while `CQS_WAIT` and `CQS_WAIT_OPERATION` propagate only when
the `inherit_err_flags` bitmask requests it.
