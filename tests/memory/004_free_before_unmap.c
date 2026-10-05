#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <errno.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    const char *name = "memory/004_free_before_unmap";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, mali_open_reason());
    uint64_t cookie = 0;
    if (p0_alloc(fd, 1, &cookie) < 0) { mali_close(fd); return test_fail(name, "MEM_ALLOC failed"); }

    void *map = p0_map(fd, cookie, 1);
    if (map == MAP_FAILED) { p0_free(fd, cookie); mali_close(fd); return test_fail(name, "initial mmap failed"); }
    ((volatile unsigned char *)map)[0] = 0x5A;

    /*
     * Lifetime probe.
     *
     * KBASE_IOCTL_MEM_ALLOC returns a cookie for 64-bit userspace, and the
     * successful mmap above consumed that cookie: kbasep_reg_mmap() clears
     * kctx->pending_regions[cookie] and releases the cookie back to the
     * bitmap. kbase_mem_free() therefore cannot resolve the cookie any more
     * and returns -EINVAL.
     *
     * That rejection is the correct r54p0 outcome, and it is precisely the
     * condition that the Project Zero 42451457 VMA-split issue exploited. A
     * free that *succeeds* here would be the anomaly worth reporting, not the
     * expected result. So this test asserts the safe direction:
     *   - MEM_FREE on the consumed cookie is refused, and
     *   - the still-mapped backing remains readable and unmodified.
     *
     * Freeing this mapping is done by munmap(), which triggers the
     * free_on_close path in kbase_context_mmap().
     */
    int free_rc = p0_free(fd, cookie);
    int free_errno = errno;
    printf("[TRACE] MEM_FREE(consumed cookie) rc=%d errno=%d (%s) cpu_vma=%p\n",
           free_rc, free_rc < 0 ? free_errno : 0,
           free_rc < 0 ? strerror(free_errno) : "accepted", map);

    if (free_rc == 0) {
        munmap(map, PAGE_SIZE); mali_close(fd);
        return test_fail(name,
            "MEM_FREE accepted an already-mapped SAME_VA cookie; "
            "backing may be freed while still mapped");
    }

    /* The VMA must remain usable until munmap; do not touch beyond this page. */
    if (((volatile unsigned char *)map)[0] != 0x5A) {
        munmap(map, PAGE_SIZE); mali_close(fd);
        return test_fail(name, "mapped backing was not stable after refused MEM_FREE");
    }
    munmap(map, PAGE_SIZE);
    mali_close(fd);
    return test_ok(name);
}
