# Architecture

```text
userspace
  |
  | /dev/mali0, ioctl, mmap
  v
Kbase (mali_kbase.ko)
  |-- GPU memory / GPU MMU bookkeeping
  |-- mmap / VMA
  |-- CSF queues / CSG / CSI / User IO
  |-- KCPU queues
  |-- CQS / fences
  v
No-Mali dummy model
```

Real CSF firmware and real GPU MMU execution are outside the No-Mali model.
