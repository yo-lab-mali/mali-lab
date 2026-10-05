# QEMU x86_64

The supplied Arm material documents a simulated-platform/x86 route that requires
source changes for CONFIG_OF=n, arch timer access, dmb(), and warning cleanup.

This directory is a secondary driver-analysis path. Keep those changes isolated
under `kernel/patches/x86/`.
