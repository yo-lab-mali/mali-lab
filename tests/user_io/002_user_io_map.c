#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>

static int setup_queue(int fd, uint64_t qva, uint8_t *group)
{
    if (p0_group_create(fd, group) < 0) return -1;
    struct kbase_ioctl_cs_queue_register reg = {
        .buffer_gpu_addr = qva,
        .buffer_size = 4 * PAGE_SIZE,
        .priority = 0,
    };
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_REGISTER, &reg, "CS_QUEUE_REGISTER") < 0) return -1;
    union kbase_ioctl_cs_queue_bind bind = {0};
    bind.in.buffer_gpu_addr = qva;
    bind.in.group_handle = *group;
    bind.in.csi_index = 0;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_BIND, &bind, "CS_QUEUE_BIND") < 0) return -1;
    /* Re-run bind is deliberately not used: one bind consumes one mmap cookie. */
    return (int)bind.out.mmap_handle;
}

int main(void)
{
    const char *name = "user_io/002_user_io_map";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, "/dev/mali0 is unavailable");
    uint64_t qva = 0;
    uint8_t group = 0;
    if (p0_alloc(fd, 4, &qva) < 0 || setup_queue(fd, qva, &group) < 0) {
        if (group) p0_group_term(fd, group);
        if (qva) p0_free(fd, qva);
        mali_close(fd);
        return test_skip(name, "CSF queue setup unavailable on this backend");
    }

    /* CS_QUEUE_BIND returns a file-offset cookie; the kernel expects exactly 3 pages. */
    union kbase_ioctl_cs_queue_bind bind = {0};
    bind.in.buffer_gpu_addr = qva;
    bind.in.group_handle = group;
    bind.in.csi_index = 0;
    /* setup_queue already consumed the cookie, so obtain a fresh queue instead. */
    struct kbase_ioctl_cs_queue_terminate oldterm = { .buffer_gpu_addr = qva };
    mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &oldterm, "CS_QUEUE_TERMINATE(rebind)");

    struct kbase_ioctl_cs_queue_register reg = { .buffer_gpu_addr = qva, .buffer_size = 4 * PAGE_SIZE, .priority = 0 };
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_REGISTER, &reg, "CS_QUEUE_REGISTER(rebind)") < 0) goto fail;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_BIND, &bind, "CS_QUEUE_BIND(rebind)") < 0) goto fail;

    void *io = mmap(NULL, BASEP_QUEUE_NR_MMAP_USER_PAGES * PAGE_SIZE,
                    PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                    (off_t)bind.out.mmap_handle);
    if (io == MAP_FAILED) goto fail;
    printf("[TRACE] user_io_handle=0x%llx cpu_va=%p pages=%d\n",
           (unsigned long long)bind.out.mmap_handle, io, BASEP_QUEUE_NR_MMAP_USER_PAGES);
    volatile unsigned char *b = io;
    b[0] = 0x11;
    b[PAGE_SIZE] = 0x22;
    b[2 * PAGE_SIZE] = 0x33;
    munmap(io, BASEP_QUEUE_NR_MMAP_USER_PAGES * PAGE_SIZE);
    printf("[TRACE] User-IO VMA closed; cookie should be released by VMA close\n");

    struct kbase_ioctl_cs_queue_terminate term = { .buffer_gpu_addr = qva };
    mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &term, "CS_QUEUE_TERMINATE(final)");
    p0_group_term(fd, group);
    p0_free(fd, qva);
    mali_close(fd);
    return test_ok(name);

fail:
    {
        struct kbase_ioctl_cs_queue_terminate term = { .buffer_gpu_addr = qva };
        mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &term, "CS_QUEUE_TERMINATE(fail-cleanup)");
    }
    p0_group_term(fd, group);
    p0_free(fd, qva);
    mali_close(fd);
    return test_fail(name, "CSF User-IO mapping lifecycle step failed");
}
