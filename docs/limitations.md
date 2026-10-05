# Limitations

1. No-Mali is a software/dummy model.
2. It does not execute real Mali firmware.
3. Dummy register operations do not emulate all hardware side effects.
4. GPU MMU IRQ/page-fault behavior is not faithfully reproduced.
5. The Arm virtual-platform Device Tree examples are not proof that stock QEMU
   implements those Mali MMIO/IRQ semantics.
6. Real GPU, power-management, firmware-execution and hardware-fault findings
   require an appropriate real platform or explicit hardware model.

Do not interpret a No-Mali result as proof of a hardware-only vulnerability.
