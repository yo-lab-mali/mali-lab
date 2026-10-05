# VMA split oracle

The P0 lifetime tests and the Project Zero 42451457 issue ("page freed while still
mapped into host userspace due to VMA split mishandling") target the same defect
class. This records how to tell a fixed r54p0 from a vulnerable one, using dmesg
output rather than inference.

## Expected on a patched r54p0

Driving the User-IO VMA split attempt produces, on dmesg:

```text
Attempt to free GPU memory whose freeing by user space is forbidden!
...
Unexpected call to split method for User IO pages mapping vma
```

The first message comes from `kbase_mem_free_region()` when the region carries
`BASEP_MEM_NO_USER_FREE`. The second comes from `kbase_csf_user_io_pages_vm_split()`,
which returns `-EINVAL` for any attempt to split a User-IO pages mapping.

The presence of `Unexpected call to split method for User IO pages mapping vma` means
the VMA split being exploited has been **prevented**. That is the fixed-driver
signature.

Note these are `pr_debug()` calls, so nothing appears unless dynamic debug is enabled
for that file and line. In r54p0 that is `mali_kbase_mem_linux.c` around lines
3328-3343:

```bash
alias ddcmd='echo $* > /sys/kernel/debug/dynamic_debug/control'
ddcmd 'file drivers/gpu/arm/midgard/mali_kbase_mem_linux.c line 3328-3343 +pt'
```

Line numbers are r54p0-specific and will drift between releases. Confirm against the
integrated source before relying on them.

## Reading the result

| Observation | Assessment |
|---|---|
| `Attempt to free GPU memory whose freeing by user space is forbidden!` | `BASEP_MEM_NO_USER_FREE` is enforced; region still driver-owned |
| `Unexpected call to split method for User IO pages mapping vma` | User-IO VMA cannot be split; exploit primitive unavailable |
| neither message, and the free succeeded | **investigate** — this is the anomalous direction |
| no dmesg at all | dynamic debug not enabled; absence proves nothing |

The absence of both messages is not evidence of vulnerability on its own. Confirm
dynamic debug is actually on before drawing any conclusion, and confirm the free
actually succeeded rather than failing for an unrelated reason.

## Why `memory/004_free_before_unmap` asserts refusal

`KBASE_IOCTL_MEM_ALLOC` returns a cookie, and the successful `mmap()` consumes it
(`kctx->pending_regions[cookie]` is cleared and the slot returned to the bitmap).
`MEM_FREE` on that consumed cookie therefore returns `-EINVAL`.

The test treats a *successful* free there as the failure condition, because a region
freed while a VMA still maps it is precisely the 42451457 defect. See
`docs/memory-model.md` for the cookie lifecycle and `docs/p0-tests.md` for the test.

## Scope limit

This is a driver-side check. It says nothing about GPU firmware, which the dummy model
does not execute, and it must not be reported as a hardware vulnerability without
real-platform validation. See `docs/limitations.md` and `docs/findings.md`.
