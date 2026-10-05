#include "../common/mali_test.h"
#include "../common/p0_helpers.h"
#include <stdio.h>

int main(void)
{
    const char *name = "user_io/002_user_io_map";
    int fd = mali_open();
    if (fd < 0) return test_skip(name, mali_open_reason());

    /*
     * The queue buffer must be a real GPU VA, not a p0_alloc() cookie: see
     * user_io/001_queue_bind.c and p0_alloc_fixed().
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
     * One register/bind pair only. bind.out.mmap_handle is a single-use mmap
     * cookie, so a second bind on the same queue is not possible and a
     * register/bind/re-register/bind sequence would only leak the first cookie.
     */
    struct kbase_ioctl_cs_queue_register reg = {0};
    reg.buffer_gpu_addr = qva;
    reg.buffer_size = 4 * PAGE_SIZE;
    reg.priority = 0;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_REGISTER, &reg, "CS_QUEUE_REGISTER") < 0)
        goto fail;

    union kbase_ioctl_cs_queue_bind bind = {0};
    bind.in.buffer_gpu_addr = qva;
    bind.in.group_handle = group;
    bind.in.csi_index = 0;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_BIND, &bind, "CS_QUEUE_BIND") < 0)
        goto fail;

    /*
     * bind.out.mmap_handle is the User-IO cookie (not a GPU VA): it selects the
     * BASEP_MEM_CSF_USER_IO_PAGES_HANDLE..BASE_MEM_COOKIE_BASE range handled by
     * kbase_csf_cpu_mmap_user_io_pages(), which maps exactly
     * BASEP_QUEUE_NR_MMAP_USER_PAGES (3) pages:
     *   page 0 doorbell register (write 0x1 to request start/resume)
     *   page 1 Input  (CS_INSERT_*, CS_EXTRACT_INIT_* virtual registers)
     *   page 2 Output (CS_EXTRACT_*, CS_ACTIVE virtual register)
     *
     * The mapping is MAP_SHARED and must span all three pages: a short mapping
     * or a private mapping is rejected by kbase_context_mmap().
     *
     * Only per-page byte probes are performed below. No doorbell write and no
     * CSF firmware instruction is emitted, because No-Mali does not execute
     * firmware and a real kick is out of scope for the P0 lifecycle surface.
     */
    void *io = mmap(NULL, BASEP_QUEUE_NR_MMAP_USER_PAGES * PAGE_SIZE,
                    PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                    (off_t)bind.out.mmap_handle);
    if (io == MAP_FAILED) goto fail;
    printf("[TRACE] user_io_handle=0x%llx cpu_va=%p pages=%zu\n",
           (unsigned long long)bind.out.mmap_handle, io, BASEP_QUEUE_NR_MMAP_USER_PAGES);
    volatile unsigned char *b = io;
    /* Page 0 is the GPU doorbell register: probe read-only, never write it.
     * Writing 0x1 there would request a queue start. */
    volatile unsigned char doorbell = b[0];
    b[PAGE_SIZE] = 0x22;        /* Input page */
    b[2 * PAGE_SIZE] = 0x33;     /* Output page */
    /* Read the two virtual-register pages back: these are CPU-visible shadow
     * pages, not GPU memory, so the writes must be observable. */
    if (b[PAGE_SIZE] != 0x22 || b[2 * PAGE_SIZE] != 0x33) {
        munmap(io, BASEP_QUEUE_NR_MMAP_USER_PAGES * PAGE_SIZE);
        goto fail;
    }
    printf("[TRACE] doorbell read=0x%02x (not written); Input/Output pages read back\n",
           doorbell);
    /* The cookie is consumed by the mapping; munmap() is the release path. */
    munmap(io, BASEP_QUEUE_NR_MMAP_USER_PAGES * PAGE_SIZE);
    printf("[TRACE] User-IO VMA closed; cookie released by VMA close\n");

    struct kbase_ioctl_cs_queue_terminate term = { .buffer_gpu_addr = qva };
    mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &term, "CS_QUEUE_TERMINATE");
    p0_group_term(fd, group);
    p0_free(fd, qva);
    mali_close(fd);
    return test_ok(name);

fail:
    {
        struct kbase_ioctl_cs_queue_terminate term_cleanup = { .buffer_gpu_addr = qva };
        mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_TERMINATE, &term_cleanup, "CS_QUEUE_TERMINATE(fail-cleanup)");
    }
    p0_group_term(fd, group);
    p0_free(fd, qva);
    mali_close(fd);
    return test_fail(name, "CSF User-IO mapping lifecycle step failed");
}