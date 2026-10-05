#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>

int main(void)
{
    const char *name = "mmap/001_cookie_lifecycle";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, mali_open_reason());
    uint64_t va = 0;
    if (p0_alloc(fd, 2, &va) < 0) { mali_close(fd); return test_fail(name, "MEM_ALLOC failed"); }

    void *p = p0_map(fd, va, 2);
    if (p == MAP_FAILED) { p0_free(fd, va); mali_close(fd); return test_fail(name, "cookie-backed mmap failed"); }
    printf("[TRACE] mmap cookie=0x%llx cpu_va=%p\n", (unsigned long long)va, p);
    munmap(p, 2 * PAGE_SIZE);

    /* Reuse the same kernel allocation path after the cookie/VMA is gone. */
    uint64_t va2 = 0;
    if (p0_alloc(fd, 2, &va2) < 0) { p0_free(fd, va); mali_close(fd); return test_fail(name, "second MEM_ALLOC failed after VMA teardown"); }
    void *p2 = p0_map(fd, va2, 2);
    if (p2 == MAP_FAILED) { p0_free(fd, va2); p0_free(fd, va); mali_close(fd); return test_fail(name, "second mmap failed"); }
    munmap(p2, 2 * PAGE_SIZE);
    p0_free(fd, va2);
    p0_free(fd, va);
    mali_close(fd);
    return test_ok(name);
}
