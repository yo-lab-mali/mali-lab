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

## Verified r54p0 P0 contract

Values below were compiled from the integrated
`AX504X08X-SW-99002-r54p0-01eac0` UAPI headers, not transcribed by hand.

| ABI object | Expected |
|---|---:|
| `KBASE_IOCTL_MEM_ALLOC` | `0xC0208005` |
| `KBASE_IOCTL_MEM_FREE` | `0x40088007` |
| `KBASE_IOCTL_CS_QUEUE_REGISTER` | `0x40108024` |
| `KBASE_IOCTL_CS_QUEUE_BIND` | `0xC0108027` |
| `KBASE_IOCTL_CS_QUEUE_TERMINATE` | `0x40088029` |
| `KBASE_IOCTL_CS_QUEUE_GROUP_CREATE` | `0xC078803F` |
| `KBASE_IOCTL_CS_QUEUE_GROUP_TERMINATE` | `0x4008802B` |
| `KBASE_IOCTL_VERSION_CHECK` | `0xC0048034` |
| `KBASE_IOCTL_SET_FLAGS` | `0x40048001` |
| `sizeof(kbase_ioctl_mem_alloc)` | `32` |
| `sizeof(kbase_ioctl_mem_free)` | `8` |
| `sizeof(kbase_ioctl_cs_queue_register)` | `16` |
| `sizeof(kbase_ioctl_cs_queue_bind)` | `16` |
| `sizeof(kbase_ioctl_cs_queue_terminate)` | `8` |
| `sizeof(kbase_ioctl_cs_queue_group_create)` | `120` |
| `sizeof(kbase_ioctl_cs_queue_group_term)` | `8` |
| `sizeof(kbase_ioctl_version_check)` | `4` |
| `sizeof(kbase_ioctl_set_flags)` | `4` |
| `BASEP_QUEUE_NR_MMAP_USER_PAGES` | `3` |

### `CS_QUEUE_GROUP_CREATE` is the easy one to get wrong

The current, unversioned `KBASE_IOCTL_CS_QUEUE_GROUP_CREATE` is nr `0x3F` with a
120-byte union. Three same-nr siblings exist and must not be confused with it:

| Symbol | Encoded value | `sizeof` union |
|---|---:|---:|
| `KBASE_IOCTL_CS_QUEUE_GROUP_CREATE` | `0xC078803F` | `120` |
| `KBASE_IOCTL_CS_QUEUE_GROUP_CREATE_1_35` | `0xC070803A` | `112` |
| `KBASE_IOCTL_CS_QUEUE_GROUP_CREATE_1_18` | `0xC028803A` | `40` |
| `KBASE_IOCTL_CS_QUEUE_GROUP_CREATE_1_6` | `0xC020802A` | `32` |

`0xC070803A` / 112 bytes is the `_1_35` compatibility variant, which is an easy
value to mistake for the current one because it shares the nr of the older
revisions. The P0 tests use the unversioned ioctl, so that is what the check
asserts.

### `VERSION_CHECK` is declared in the CSF header

`KBASE_IOCTL_VERSION_CHECK` is nr `52` in
`include/uapi/gpu/arm/midgard/csf/mali_kbase_csf_ioctl.h`, not in the core
`mali_kbase_ioctl.h`. `KBASE_IOCTL_SET_FLAGS` is nr `1` in the core header.
Both are asserted so a header set that only partially exposes the CSF surface
fails the check instead of failing later at runtime.

## U/K version gate

r54p0 declares `BASE_UK_VERSION_MAJOR`/`MINOR` as `1.36`. Capabilities are
resolved against the *negotiated* version, and the check asserts
`MINOR >= 35` because `MALI_KBASE_CAP_CSG_CS_USER_PAGE_ALLOCATION` requires
`1.35`. Below that version, User-IO pages are allocated at bind time rather than
at CSG creation, which changes the lifetime the User-IO P0 tests are asserting.

The check is compile-only, so it also works when `CC` is a cross compiler. A
failure is fatal and prints the header locations, compiler output, and expected
contract. The generated probe is retained in `build/abi-check/` for debugging.
