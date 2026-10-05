#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>

int main(void)
{
    const char *name = "user_io/001_queue_bind";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, mali_open_reason());

    /*
     * CS_QUEUE_REGISTER resolves buffer_gpu_addr with
     * kbase_region_tracker_find_region_enclosing_address() and rejects anything
     * that is not a live KBASE_MEM_TYPE_NATIVE region (-ENOENT). A p0_alloc()
     * cookie is not such an address: it is an mmap handle, not a GPU VA. So the
     * queue buffer is allocated with BASE_MEM_FIXED at a chosen GPU VA, which is
     * the only way a 64-bit non-compat context can obtain one.
     */
    uint64_t qva = 0;
    uint8_t group = 0;
    if (p0_alloc_fixed(fd, 4, &qva) < 0) {
        mali_close(fd);
        return test_skip(name, "MEM_ALLOC_EX with BASE_MEM_FIXED unavailable");
    }

    if (p0_group_create(fd, &group) < 0) {
        p0_free(fd, qva);
        mali_close(fd);
        return test_skip(name, "CSF queue-group creation unavailable on this backend");
    }

    /*
     * kbase_csf_queue_register() additionally requires buffer_size to be a power
     * of two in [CS_RING_BUFFER_MIN_SIZE, CS_RING_BUFFER_MAX_SIZE] and
     * buffer_gpu_addr to be page aligned, else -EINVAL.
     */
    struct kbase_ioctl_cs_queue_register reg = {0};
    reg.buffer_gpu_addr = qva;
    reg.buffer_size = 4 * PAGE_SIZE;
    reg.priority = 0;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_REGISTER, &reg, "CS_QUEUE_REGISTER") < 0) {
        p0_group_term(fd, group);
        p0_free(fd, qva);
        mali_close(fd);
        return test_fail(name, "CS_QUEUE_REGISTER rejected a live NATIVE region");
    }

    union kbase_ioctl_cs_queue_bind bind = {0};
    bind.in.buffer_gpu_addr = qva;
    bind.in.group_handle = group;
    bind.in.csi_index = 0;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_BIND, &bind, "CS_QUEUE_BIND") < 0) {
        struct kbase_ioctl_cs_queue_terminate t = { .buffer_gpu_addr = qva };
        mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &t, "CS_QUEUE_TERMINATE(cleanup)");
        p0_group_term(fd, group);
        p0_free(fd, qva);
        mali_close(fd);
        return test_fail(name, "CS_QUEUE_BIND failed");
    }
    /* mmap_handle is a cookie, not a GPU VA: it selects the User-IO page range. */
    if (!bind.out.mmap_handle) {
        struct kbase_ioctl_cs_queue_terminate t = { .buffer_gpu_addr = qva };
        mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &t, "CS_QUEUE_TERMINATE(no-handle)");
        p0_group_term(fd, group);
        p0_free(fd, qva);
        mali_close(fd);
        return test_fail(name, "CS_QUEUE_BIND returned a zero User-IO handle");
    }
    printf("[TRACE] queue gpu_va=0x%llx group=%u user_io_handle=0x%llx\n",
           (unsigned long long)qva, group, (unsigned long long)bind.out.mmap_handle);

    struct kbase_ioctl_cs_queue_terminate term = { .buffer_gpu_addr = qva };
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &term, "CS_QUEUE_TERMINATE") < 0) {
        p0_group_term(fd, group);
        p0_free(fd, qva);
        mali_close(fd);
        return test_fail(name, "CS_QUEUE_TERMINATE failed");
    }
    if (p0_group_term(fd, group) < 0) { p0_free(fd, qva); mali_close(fd); return test_fail(name, "CS_QUEUE_GROUP_TERMINATE failed"); }
    p0_free(fd, qva);
    mali_close(fd);
    return test_ok(name);
}