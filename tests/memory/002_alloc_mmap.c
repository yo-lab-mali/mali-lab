#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>
#include <string.h>
#include <errno.h>

/*
 * MEM_ALLOC yields a cookie, not a GPU VA, on every 64-bit context:
 * kbase_create_context() sets KCTX_FORCE_SAME_VA unconditionally for
 * non-compat callers, and kbase_kbase_api_mem_alloc() then forces
 * flags |= BASE_MEM_SAME_VA. A successful mmap() is what consumes that cookie
 * (kbasep_reg_mmap() clears kctx->pending_regions[cookie]) and kbase_context_mmap()
 * sets free_on_close so munmap() releases the region.
 *
 * MEM_FREE on the consumed cookie must therefore be *refused*. Accepting it
 * would be a double free of memory the driver has already released, so the
 * refusal is the assertion, not a tolerated error.
 */
int main(void)
{
    const char *name = "memory/002_alloc_mmap";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, mali_open_reason());
    uint64_t cookie = 0;
    void *map = MAP_FAILED;

    if (p0_alloc(fd, P0_PAGES, &cookie) < 0) {
        mali_close(fd); return test_fail(name, "MEM_ALLOC failed");
    }
    map = p0_map(fd, cookie, P0_PAGES);
    if (map == MAP_FAILED) {
        p0_free(fd, cookie); mali_close(fd);
        return test_fail(name, "mmap of allocation failed");
    }
    memset(map, 0xA5, P0_PAGES * PAGE_SIZE);
    printf("[TRACE] cookie=0x%llx cpu_va=%p bytes=%lu\n",
           (unsigned long long)cookie, map, P0_PAGES * PAGE_SIZE);

    munmap(map, P0_PAGES * PAGE_SIZE);

    errno = 0;
    if (p0_free(fd, cookie) == 0) {
        mali_close(fd);
        return test_fail(name, "MEM_FREE accepted an already-mapped cookie");
    }
    if (errno != EINVAL) {
        char detail[160]; test_errno_detail(detail, sizeof detail, "MEM_FREE");
        mali_close(fd); return test_fail(name, detail);
    }
    printf("[TRACE] MEM_FREE on consumed cookie refused errno=%d (EINVAL)\n", EINVAL);

    mali_close(fd);
    return test_ok(name);
}