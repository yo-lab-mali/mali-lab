#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>

int main(void)
{
    const char *name = "memory/001_alloc_free";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, mali_open_reason());

    uint64_t va = 0;
    if (p0_alloc(fd, P0_PAGES, &va) < 0) {
        mali_close(fd);
        return test_fail(name, "MEM_ALLOC failed");
    }
    printf("[TRACE] allocated gpu_va=0x%llx pages=%lu\n",
           (unsigned long long)va, P0_PAGES);

    if (p0_free(fd, va) < 0) {
        mali_close(fd);
        return test_fail(name, "MEM_FREE failed for live allocation");
    }
    printf("[TRACE] freed gpu_va=0x%llx\n", (unsigned long long)va);
    mali_close(fd);
    return test_ok(name);
}
