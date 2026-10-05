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
