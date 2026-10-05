# CI

CI should initially validate:
- repository structure
- shell syntax
- host-side test compilation
- documentation/config consistency

Booting QEMU and executing the Mali driver should be an explicit CI job because
it requires large external kernel/rootfs inputs.
