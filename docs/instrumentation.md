# Instrumentation

Recommended layers:

1. dynamic_debug for Kbase source
2. object lifetime logging
3. KASAN/KFENCE
4. lockdep
5. QEMU/GDB when needed

Keep logs reproducible and attach metadata to every result.
