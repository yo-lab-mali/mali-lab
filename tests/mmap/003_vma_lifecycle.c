#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>
#include <errno.h>

int main(void)
{
    const char *name = "mmap/003_vma_lifecycle";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, "/dev/mali0 is unavailable");
    uint64_t va = 0;
    if (p0_alloc(fd, 1, &va) < 0) { mali_close(fd); return test_fail(name, "MEM_ALLOC failed"); }
    void *p = p0_map(fd, va, 1);
    if (p == MAP_FAILED) { p0_free(fd, va); mali_close(fd); return test_fail(name, "mmap failed"); }
    ((volatile unsigned int *)p)[0] = 0x13572468U;
    munmap(p, PAGE_SIZE);
    printf("[TRACE] VMA closed for gpu_va=0x%llx\n", (unsigned long long)va);

    if (p0_free(fd, va) < 0) { mali_close(fd); return test_fail(name, "MEM_FREE after VMA close failed"); }

    /* Stale file offset should no longer identify a live region. */
    errno = 0;
    void *stale = p0_map(fd, va, 1);
    if (stale != MAP_FAILED) {
        munmap(stale, PAGE_SIZE);
        mali_close(fd);
        return test_fail(name, "stale GPU VA unexpectedly mapped after free");
    }
    printf("[TRACE] stale mmap rejected errno=%d\n", errno);
    mali_close(fd);
    return test_ok(name);
}
