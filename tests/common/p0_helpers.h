#ifndef P0_HELPERS_H
#define P0_HELPERS_H

#include "mali_test.h"
#include "mali_uapi.h"
#include <stdint.h>
#include <stddef.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#define P0_PAGES 4UL
#define P0_ALLOC_FLAGS (BASE_MEM_PROT_CPU_RD | BASE_MEM_PROT_CPU_WR | \
                        BASE_MEM_PROT_GPU_RD | BASE_MEM_PROT_GPU_WR)

/*
 * KBASE_IOCTL_MEM_ALLOC returns a *cookie* for 64-bit userspace, not a real
 * GPU VA: kbase_mem_alloc() binds the region to a pending cookie and returns
 * (cookie + PFN_DOWN(BASE_MEM_COOKIE_BASE)) << PAGE_SHIFT. The cookie is the
 * only valid mmap() offset, and a successful mapping consumes it.
 *
 * The cookie is not an artefact of the flags in P0_ALLOC_FLAGS. Two driver
 * decisions make it unavoidable for KBASE_IOCTL_MEM_ALLOC:
 *   1. kbase_create_context() sets KCTX_FORCE_SAME_VA unconditionally on a
 *      64-bit build for callers that are not KCTX_COMPAT.
 *   2. kbase_kbase_api_mem_alloc() then adds flags |= BASE_MEM_SAME_VA to any
 *      allocation that is neither executable nor fixed/fixable.
 * (kbase_api_mem_alloc() is itself a wrapper: it fills in a
 * union kbase_ioctl_mem_alloc_ex with fixed_address = 0 and calls
 * kbase_api_mem_alloc_ex(), so MEM_ALLOC can never request a specific VA.)
 *
 * A real GPU VA is still reachable, but only through KBASE_IOCTL_MEM_ALLOC_EX
 * with BASE_MEM_FIXED -- see p0_alloc_fixed() below. p0_alloc() itself cannot
 * produce one.
 *
 * Consequence for lifetime tests: after p0_map() succeeds, the cookie is no
 * longer a pending region, so KBASE_IOCTL_MEM_FREE on that same value is
 * rejected (-EINVAL) rather than freeing anything. Freeing SAME_VA/cookie
 * memory is only possible via munmap(). Tests that want to exercise the free
 * path must therefore either not map first, or explicitly free a *non*-mapped
 * allocation. See docs/memory-model.md and docs/vma-split-oracle.md.
 */
static inline int p0_alloc(int fd, size_t pages, uint64_t *cookie)
{
    union kbase_ioctl_mem_alloc a = {0};
    a.in.va_pages = pages;
    a.in.commit_pages = pages;
    a.in.extension = 0;
    a.in.flags = P0_ALLOC_FLAGS;
    if (mali_ioctl(fd, KBASE_IOCTL_MEM_ALLOC, &a, "MEM_ALLOC") < 0)
        return -1;
    if (!a.out.gpu_va)
        return -1;
    *cookie = a.out.gpu_va;
    return 0;
}

static inline int p0_free(int fd, uint64_t cookie)
{
    struct kbase_ioctl_mem_free f = { .gpu_addr = cookie };
    return mali_ioctl(fd, KBASE_IOCTL_MEM_FREE, &f, "MEM_FREE");
}

/*
 * The offset must be the cookie returned by p0_alloc(), and the mapping must be
 * MAP_SHARED with a non-zero length: kbase_context_mmap() rejects
 * nr_pages == 0 (-EINVAL) and any non-MAP_SHARED mapping (-EINVAL).
 * For SAME_VA/cookie memory the region is freed on VMA close.
 */
static inline void *p0_map(int fd, uint64_t cookie, size_t pages)
{
    if (pages == 0) return MAP_FAILED;
    return mmap(NULL, pages * PAGE_SIZE, PROT_READ | PROT_WRITE,
                MAP_SHARED, fd, (off_t)cookie);
}

static inline int p0_group_create(int fd, uint8_t *handle)
{
    union kbase_ioctl_cs_queue_group_create g = {0};
    g.in.tiler_mask = ~0ULL;
    g.in.fragment_mask = ~0ULL;
    g.in.compute_mask = ~0ULL;
    g.in.cs_min = 1;
    g.in.priority = 0;
    g.in.tiler_max = 1;
    g.in.fragment_max = 1;
    g.in.compute_max = 1;
    g.in.csi_handlers = 0;
    /*
     * g.in.padding[] must be zero: check_padding_KBASE_IOCTL_CS_QUEUE_GROUP_CREATE()
     * rejects any non-zero padding byte with -EINVAL. The = {0} initialiser
     * already guarantees this, so nothing more is required here.
     *
     * User-IO page allocation happens at CSG creation only when the negotiated
     * U/K version is >= 1.35 (MALI_KBASE_CAP_CSG_CS_USER_PAGE_ALLOCATION).
     * mali_open() requests BASE_UK_VERSION_MINOR, so r54p0 satisfies this.
     */
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_GROUP_CREATE, &g, "CS_QUEUE_GROUP_CREATE") < 0)
        return -1;
    *handle = g.out.group_handle;
    return 0;
}

static inline int p0_group_term(int fd, uint8_t handle)
{
    struct kbase_ioctl_cs_queue_group_term t = {0};
    t.group_handle = handle;
    return mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_GROUP_TERMINATE, &t, "CS_QUEUE_GROUP_TERMINATE");
}

/*
 * Base of FIXED_VA_ZONE for a non-compat 64-bit context.
 *
 * kbase_reg_zone_fixed_va_init() (mali_kbase_reg_track.c) sets
 *   base_pfn  = KBASE_REG_ZONE_EXEC_VA_BASE_64 + KBASE_REG_ZONE_EXEC_VA_SIZE
 *             = 2^47 + 4GiB = 0x801000000000
 *   va_size   = 2^48 - 0x801000000000
 * so the zone runs up to but excluding 2^48. Taking the zone base rather than
 * some arbitrary high address matters only because kbase_alloc_free_region()
 * does not range-check start_pfn against the zone: the kernel would accept an
 * address outside the zone and the failure would surface much later, in the
 * MMU mapping.
 */
#define P0_FIXED_VA_BASE 0x801000000000ULL

/*
 * p0_alloc_fixed - allocate at a caller-chosen GPU VA, i.e. return a real VA
 * rather than an mmap cookie.
 *
 * KBASE_IOCTL_MEM_ALLOC_EX (0xC040803B, nr 59, 64 bytes) is the only allocation
 * ioctl with a fixed_address field. Requesting BASE_MEM_FIXED suppresses the
 * SAME_VA upgrade, because kbase_api_mem_alloc_ex() only adds BASE_MEM_SAME_VA
 * when the allocation is neither GPU-executable nor fixed/fixable:
 *
 *   if ((!kbase_ctx_flag(kctx, KCTX_COMPAT)) && kbase_ctx_flag(kctx, KCTX_FORCE_SAME_VA))
 *           if (!gpu_executable && !fixed_or_fixable)
 *                   flags |= BASE_MEM_SAME_VA;
 *
 * and it takes gpu_va from the request rather than from the allocator. The two
 * cannot be combined: kbase_check_alloc_flags() rejects SAME_VA with
 * FIXED/FIXABLE.
 *
 * Preconditions the driver enforces, so a caller does not have to rediscover them:
 *   - fixed_address must be non-zero and page-aligned when FIXED, else -EINVAL
 *   - fixed_address must be zero when not FIXED, else -EINVAL
 *   - FIXED while kctx->num_fixable_allocs > 0, or FIXABLE while
 *     num_fixed_allocs > 0, else -EINVAL (the two are never meant to coexist)
 *   - in.extra[3] must be zero, else -EINVAL
 *     (check_padding_KBASE_IOCTL_MEM_ALLOC_EX())
 *
 * Lifetime: unlike p0_alloc() this region is not SAME_VA, so there is no cookie
 * and p0_map() does not apply. Release it with p0_free() on the returned VA.
 * Because it never enters num_fixable_allocs, it does not block FIXABLE
 * allocations either.
 */
static inline int p0_alloc_fixed(int fd, size_t pages, uint64_t *gpu_va)
{
    union kbase_ioctl_mem_alloc_ex a = {0};
    a.in.va_pages = pages;
    a.in.commit_pages = pages;
    a.in.extension = 0;
    a.in.flags = P0_ALLOC_FLAGS | BASE_MEM_FIXED;
    a.in.fixed_address = P0_FIXED_VA_BASE;
    /* a.in.extra[] must stay zero: see the padding note above. */
    if (mali_ioctl(fd, KBASE_IOCTL_MEM_ALLOC_EX, &a, "MEM_ALLOC_EX") < 0)
        return -1;
    /* The driver returns the aligned request verbatim; anything else would mean
     * the FIXED path was not taken and the value is not a usable queue buffer. */
    if (a.out.gpu_va != P0_FIXED_VA_BASE)
        return -1;
    *gpu_va = a.out.gpu_va;
    return 0;
}

#endif
