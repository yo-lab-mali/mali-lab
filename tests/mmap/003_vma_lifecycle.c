#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>
#include <errno.h>

/*
 * Full VMA lifecycle for a cookie-backed allocation: map, touch, unmap. The
 * mmap() consumes the cookie (kbasep_reg_mmap() clears pending_regions[cookie])
 * and munmap() releases the region (free_on_close), so afterwards neither the
 * cookie as an mmap offset nor as a MEM_FREE argument may still resolve.
 * Both must be refused with -EINVAL.
 */
int main(void)
{
    const char *name = "mmap/003_vma_lifecycle";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, mali_open_reason());
    uint64_t cookie = 0;
    if (p0_alloc(fd, 1, &cookie) < 0) { mali_close(fd); return test_fail(name, "MEM_ALLOC failed"); }
    void *p = p0_map(fd, cookie, 1);
    if (p == MAP_FAILED) { p0_free(fd, cookie); mali_close(fd); return test_fail(name, "mmap failed"); }
    ((volatile unsigned int *)p)[0] = 0x13572468U;
    munmap(p, PAGE_SIZE);
    printf("[TRACE] VMA closed for cookie=0x%llx\n", (unsigned long long)cookie);

    errno = 0;
    if (p0_free(fd, cookie) == 0) {
        mali_close(fd);
        return test_fail(name, "MEM_FREE accepted a cookie consumed by VMA close");
    }
    if (errno != EINVAL) {
        char detail[160]; test_errno_detail(detail, sizeof detail, "MEM_FREE");
        mali_close(fd); return test_fail(name, detail);
    }

    /* Stale file offset should no longer identify a live region. */
    errno = 0;
    void *stale = p0_map(fd, cookie, 1);
    if (stale != MAP_FAILED) {
        munmap(stale, PAGE_SIZE);
        mali_close(fd);
        return test_fail(name, "stale cookie unexpectedly mapped after VMA close");
    }
    printf("[TRACE] stale remap rejected errno=%d; MEM_FREE rejected errno=%d\n", errno, EINVAL);
    mali_close(fd);
    return test_ok(name);
}