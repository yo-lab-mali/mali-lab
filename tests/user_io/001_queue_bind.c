#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>

int main(void)
{
    const char *name = "user_io/001_queue_bind";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, "/dev/mali0 is unavailable");

    uint64_t qva = 0;
    uint8_t group = 0;
    if (p0_alloc(fd, 4, &qva) < 0) { mali_close(fd); return test_skip(name, "MEM_ALLOC unavailable; CSF prerequisites not active"); }
    if (p0_group_create(fd, &group) < 0) {
        p0_free(fd, qva); mali_close(fd);
        return test_skip(name, "CSF queue-group creation unavailable on this backend");
    }

    struct kbase_ioctl_cs_queue_register reg = {0};
    reg.buffer_gpu_addr = qva;
    reg.buffer_size = 4 * PAGE_SIZE;
    reg.priority = 0;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_REGISTER, &reg, "CS_QUEUE_REGISTER") < 0) {
        p0_group_term(fd, group); p0_free(fd, qva); mali_close(fd);
        return test_fail(name, "CS_QUEUE_REGISTER failed");
    }

    union kbase_ioctl_cs_queue_bind bind = {0};
    bind.in.buffer_gpu_addr = qva;
    bind.in.group_handle = group;
    bind.in.csi_index = 0;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_BIND, &bind, "CS_QUEUE_BIND") < 0) {
        struct kbase_ioctl_cs_queue_terminate t = { .buffer_gpu_addr = qva };
        mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &t, "CS_QUEUE_TERMINATE(cleanup)");
        p0_group_term(fd, group); p0_free(fd, qva); mali_close(fd);
        return test_fail(name, "CS_QUEUE_BIND failed");
    }
    printf("[TRACE] queue gpu_va=0x%llx group=%u user_io_handle=0x%llx\n",
           (unsigned long long)qva, group, (unsigned long long)bind.out.mmap_handle);

    struct kbase_ioctl_cs_queue_terminate term = { .buffer_gpu_addr = qva };
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &term, "CS_QUEUE_TERMINATE") < 0) {
        p0_group_term(fd, group); p0_free(fd, qva); mali_close(fd);
        return test_fail(name, "CS_QUEUE_TERMINATE failed");
    }
    if (p0_group_term(fd, group) < 0) { p0_free(fd, qva); mali_close(fd); return test_fail(name, "CS_QUEUE_GROUP_TERMINATE failed"); }
    p0_free(fd, qva);
    mali_close(fd);
    return test_ok(name);
}
