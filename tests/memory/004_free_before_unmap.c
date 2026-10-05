#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>

int main(void)
{
    const char *name = "memory/004_free_before_unmap";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, "/dev/mali0 is unavailable");
    uint64_t va = 0;
    if (p0_alloc(fd, 1, &va) < 0) { mali_close(fd); return test_fail(name, "MEM_ALLOC failed"); }

    void *map = p0_map(fd, va, 1);
    if (map == MAP_FAILED) { p0_free(fd, va); mali_close(fd); return test_fail(name, "initial mmap failed"); }
    ((volatile unsigned char *)map)[0] = 0x5A;

    /* Lifetime probe: drop the user allocation handle while the VMA remains open. */
    if (p0_free(fd, va) < 0) {
        munmap(map, PAGE_SIZE); mali_close(fd);
        return test_fail(name, "MEM_FREE failed while VMA remained mapped");
    }
    printf("[TRACE] MEM_FREE completed while cpu_vma=%p remained mapped\n", map);

    /* The VMA must remain usable until munmap; do not touch beyond this page. */
    if (((volatile unsigned char *)map)[0] != 0x5A) {
        munmap(map, PAGE_SIZE); mali_close(fd);
        return test_fail(name, "mapped backing was not stable after MEM_FREE");
    }
    munmap(map, PAGE_SIZE);
    mali_close(fd);
    return test_ok(name);
}
