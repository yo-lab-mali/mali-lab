# P0 UAPI ABI check

`make tests` runs `scripts/configure-abi-check.sh` before compiling the P0 binaries.

The check requires the integrated kernel tree to contain:

```text
include/uapi/gpu/arm/midgard/mali_kbase_ioctl.h
include/uapi/gpu/arm/midgard/mali_base_common_kernel.h
include/uapi/gpu/arm/midgard/csf/mali_kbase_csf_ioctl.h
```

It then compiles a probe with the same include paths as the tests. `_Static_assert`
checks validate both the encoded ioctl values and the sizes of every ABI object
used by the current P0 memory/mmap/User-IO tests.

Expected r54p0 P0 contract:

| ABI object | Expected |
|---|---:|
| `KBASE_IOCTL_MEM_ALLOC` | `0xC0208005` |
| `KBASE_IOCTL_MEM_FREE` | `0x40088007` |
| `KBASE_IOCTL_CS_QUEUE_REGISTER` | `0x40108024` |
| `KBASE_IOCTL_CS_QUEUE_BIND` | `0xC0108027` |
| `KBASE_IOCTL_CS_QUEUE_TERMINATE` | `0x40108029` |
| `KBASE_IOCTL_CS_QUEUE_GROUP_CREATE` | `0xC058803A` |
| `KBASE_IOCTL_CS_QUEUE_GROUP_TERMINATE` | `0x4008802B` |
| `sizeof(kbase_ioctl_mem_alloc)` | `32` |
| `sizeof(kbase_ioctl_mem_free)` | `8` |
| `sizeof(kbase_ioctl_cs_queue_register)` | `16` |
| `sizeof(kbase_ioctl_cs_queue_bind)` | `16` |
| `sizeof(kbase_ioctl_cs_queue_terminate)` | `8` |
| `sizeof(kbase_ioctl_cs_queue_group_create)` | `112` |
| `sizeof(kbase_ioctl_cs_queue_group_term)` | `8` |

The check is compile-only, so it also works when `CC` is a cross compiler. A
failure is fatal and prints the header locations, compiler output, and expected
contract. The generated probe is retained in `build/abi-check/` for debugging.
