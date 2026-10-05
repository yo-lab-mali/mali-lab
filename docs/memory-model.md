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
