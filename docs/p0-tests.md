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

## Memory P0

- `memory/001_alloc_free`: allocation -> free.
- `memory/002_alloc_mmap`: allocation -> mmap -> CPU access -> munmap -> free.
- `memory/003_mmap_unmap`: repeated VMA creation/teardown against one allocation.
- `memory/004_free_before_unmap`: free the userspace allocation handle while the VMA
  remains mapped, verify the mapping remains readable, then close the VMA.

The last test is a lifetime invariant check, not an exploit: the backing object must
remain valid until the VMA reference is released.

## mmap/VMA P0

- `mmap/001_cookie_lifecycle`: map/unmap, then allocate/map again to exercise cookie
  and VMA release/reuse paths.
- `mmap/003_vma_lifecycle`: close the VMA, free the region, and verify the stale GPU
  offset is not accepted as a new mapping.

## CSF User-IO P0

- `user_io/001_queue_bind`: allocate queue backing, create a CSF queue group, register
  and bind a queue, then terminate queue/group and release backing.
- `user_io/002_user_io_map`: bind a queue, mmap the returned User-IO handle for exactly
  `BASEP_QUEUE_NR_MMAP_USER_PAGES` pages, touch the input/output/doorbell mappings,
  munmap, then terminate and release the queue.

The three-page User-IO mapping and cookie offset follow the documented Kbase mmap path.
No queue kick or firmware instruction execution is attempted.

## Why this is safe for No-Mali

These are deterministic lifecycle/regression tests. They do not construct malformed
firmware commands, trigger GPU faults, or attempt a privilege boundary bypass.
No-Mali can therefore cover the Kbase bookkeeping and VMA/object-lifetime portions;
real hardware is still required for faithful GPU MMU IRQ and CSF firmware behavior.
