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
