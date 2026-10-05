#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>
#include <string.h>

int main(void)
{
    const char *name = "memory/002_alloc_mmap";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, "/dev/mali0 is unavailable");
    uint64_t va = 0;
    void *map = MAP_FAILED;

    if (p0_alloc(fd, P0_PAGES, &va) < 0) {
        mali_close(fd); return test_fail(name, "MEM_ALLOC failed");
    }
    map = p0_map(fd, va, P0_PAGES);
    if (map == MAP_FAILED) {
        p0_free(fd, va); mali_close(fd);
        return test_fail(name, "mmap of allocation failed");
    }
    memset(map, 0xA5, P0_PAGES * PAGE_SIZE);
    printf("[TRACE] gpu_va=0x%llx cpu_va=%p bytes=%lu\n",
           (unsigned long long)va, map, P0_PAGES * PAGE_SIZE);

    munmap(map, P0_PAGES * PAGE_SIZE);
    if (p0_free(fd, va) < 0) {
        mali_close(fd); return test_fail(name, "MEM_FREE after munmap failed");
    }
    mali_close(fd);
    return test_ok(name);
}
