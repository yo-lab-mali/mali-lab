# Kernel patches

Patches are intentionally kept as placeholders until the exact Linux kernel tree
and r54p0 integration baseline are selected.

Do not apply generic patches blindly. The supplied Arm material documents an x86
simulated-platform route requiring CONFIG_OF/timer/dmb/warning changes; those
changes belong under `x86/`.
