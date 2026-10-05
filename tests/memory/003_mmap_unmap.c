#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>
#include <string.h>

int main(void)
{
    const char *name = "memory/003_mmap_unmap";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, "/dev/mali0 is unavailable");
    uint64_t va = 0;
    if (p0_alloc(fd, 1, &va) < 0) { mali_close(fd); return test_fail(name, "MEM_ALLOC failed"); }

    for (unsigned i = 0; i < 8; ++i) {
        void *p = p0_map(fd, va, 1);
        if (p == MAP_FAILED) {
            p0_free(fd, va); mali_close(fd);
            return test_fail(name, "repeated mmap failed");
        }
        ((volatile unsigned char *)p)[0] = (unsigned char)i;
        munmap(p, PAGE_SIZE);
    }
    printf("[TRACE] completed 8 mmap/munmap cycles for gpu_va=0x%llx\n",
           (unsigned long long)va);

    if (p0_free(fd, va) < 0) { mali_close(fd); return test_fail(name, "MEM_FREE failed"); }
    mali_close(fd);
    return test_ok(name);
}
