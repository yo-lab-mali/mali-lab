#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>
#include <errno.h>

/*
 * The MEM_ALLOC cookie is single use. kbasep_reg_mmap() clears the pending
 * region on the first successful map, and kbase_context_mmap() sets
 * free_on_close so munmap() releases the region. Every later attempt to reuse
 * the same cookie fails with -EINVAL, because kbase_get_unmapped_area() finds no
 * pending region for it.
 *
 * Mapping repeatedly with one cookie is therefore not a legal lifecycle but a
 * double map of already-released memory, so the loop below asserts that all of
 * those attempts are refused.
 */
#define P0_REMAP_ATTEMPTS 8

int main(void)
{
    const char *name = "memory/003_mmap_unmap";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, mali_open_reason());
    uint64_t cookie = 0;
    if (p0_alloc(fd, 1, &cookie) < 0) { mali_close(fd); return test_fail(name, "MEM_ALLOC failed"); }

    void *p = p0_map(fd, cookie, 1);
    if (p == MAP_FAILED) { p0_free(fd, cookie); mali_close(fd); return test_fail(name, "initial mmap failed"); }
    ((volatile unsigned char *)p)[0] = 0x5A;
    munmap(p, PAGE_SIZE);
    printf("[TRACE] mapped and unmapped cookie=0x%llx\n", (unsigned long long)cookie);

    for (unsigned i = 0; i < P0_REMAP_ATTEMPTS; ++i) {
        errno = 0;
        void *again = p0_map(fd, cookie, 1);
        if (again != MAP_FAILED) {
            munmap(again, PAGE_SIZE);
            mali_close(fd);
            return test_fail(name, "released cookie was mapped again");
        }
        if (errno != EINVAL) {
            char detail[160]; test_errno_detail(detail, sizeof detail, "remap");
            mali_close(fd); return test_fail(name, detail);
        }
    }
    printf("[TRACE] %d stale remap attempts all refused errno=%d (EINVAL)\n",
           P0_REMAP_ATTEMPTS, EINVAL);

    mali_close(fd);
    return test_ok(name);
}