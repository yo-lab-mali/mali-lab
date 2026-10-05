# Build

## Host dependencies

Typical Linux host requirements include:

- git
- make
- gcc/binutils
- cross compiler for AArch64
- QEMU system emulator
- cpio/tar
- an initramfs/rootfs builder

The scripts intentionally avoid downloading the Arm driver automatically.

## Flow

```text
verify exact r54p0 archive
        |
integrate Kbase into Linux
        |
apply local research patches
        |
configure No-Mali + CSF
        |
build kernel
        |
build rootfs/tests
        |
boot QEMU
```
