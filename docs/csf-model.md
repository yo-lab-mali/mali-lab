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
