# Firmware

The supplied documentation describes a separate static-analysis workflow for
`mali_csffw.bin`.

No-Mali does not execute this firmware.

Keep firmware work under `firmware/` and do not commit vendor firmware binaries.

## Decoding the image

The CSF itself executes **ARMv7-M Thumb** instructions. Parsing begins in
`kbase_csf_firmware_load_init()`, and each section is parsed by `load_firmware_entry()`
switching on the `CSF_FIRMWARE_ENTRY_TYPE_...` section type.

To find the code and the entry point in the image:

- **Code** lives in sections of type `CSF_FIRMWARE_ENTRY_TYPE_INTERFACE` that have the
  `CSF_FIRMWARE_ENTRY_EXECUTE` flag set.
- **Vector table** lives in a `CSF_FIRMWARE_ENTRY_TYPE_INTERFACE` section *without*
  that flag, located at CSF address `0x0`. Offset `0x4` within it is the reset handler
  address, with bit 0 set per the ARMv7-M specification.
- The entry point is then `code_start + ((reset_handler - 1) - code_load_address)`.

In the documented worked example, code is at image offset `0x282c..0x14d2c` loading at
CSF address `0x00800000`, the vector table is at `0x0114c..0x011ec` with reset handler
at `0x01150`:

```text
0x282c + ((0x00801fcd - 1) - 0x00800000) == 0x47f8
```

Disassemble from there:

```bash
arm-linux-gnueabihf-objdump -D --start-address=$((0x47f8)) \
  --stop-address=$((0x14d2c)) -m armv7e-m -Mforce-thumb -b binary mali_csffw.bin
```

Note the code range can extend to *lower* addresses than the reset handler, so starting
disassembly at the reset handler misses earlier code.

## Compiling in the parser under No-Mali

No-Mali builds exclude the firmware objects, so the image is not parsed. To decode it
in a virtual environment, edit `drivers/gpu/arm/midgard/csf/Kbuild` so the `NO_MALI`
branch includes the firmware parsing objects:

```make
ifeq ($(CONFIG_MALI_NO_MALI),y)
mali_kbase-y += csf/mali_kbase_csf_firmware.o
mali_kbase-y += csf/mali_kbase_csf_fw_io_no_mali.o
else
mali_kbase-y += csf/mali_kbase_csf_firmware.o
```

Then add a `printk()` in `parse_memory_setup_entry()` to dump each section, and on
`CONFIG_OF=n` builds set `kbdev->reg_size = 0x200000ul` in
`kbase_gpu_device_create()`. Install the image and run any GPU application to trigger
the load:

```bash
sudo cp -a mali_csffw.bin /lib/firmware/mali_csffw.bin
sudo insmod mali_kbase.ko
../libGPUCounters/build/examples/api-example
```

Expected section dump:

```text
FW interface mem '' offset 0x0282c data_end 0x14d2c loads at CSF addr 0x00800000..0x00820000 flags=0x0000000d EXEC=yes
```

**Driver startup will fail in this configuration**, by design — the point is to decode
the image, not to obtain a working driver. Warnings afterwards are expected and can be
ignored for decoding purposes. Do not treat a resulting crash here as a finding.
