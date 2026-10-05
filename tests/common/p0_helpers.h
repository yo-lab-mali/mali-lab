#ifndef P0_HELPERS_H
#define P0_HELPERS_H

#include "mali_test.h"
#include "mali_uapi.h"
#include <stdint.h>
#include <stddef.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#define P0_PAGES 4UL
#define P0_ALLOC_FLAGS (BASE_MEM_PROT_CPU_RD | BASE_MEM_PROT_CPU_WR | \
                        BASE_MEM_PROT_GPU_RD | BASE_MEM_PROT_GPU_WR)

static inline int p0_alloc(int fd, size_t pages, uint64_t *gpu_va)
{
    union kbase_ioctl_mem_alloc a = {0};
    a.in.va_pages = pages;
    a.in.commit_pages = pages;
    a.in.extension = 0;
    a.in.flags = P0_ALLOC_FLAGS;
    if (mali_ioctl(fd, KBASE_IOCTL_MEM_ALLOC, &a, "MEM_ALLOC") < 0)
        return -1;
    if (!a.out.gpu_va)
        return -1;
    *gpu_va = a.out.gpu_va;
    return 0;
}

static inline int p0_free(int fd, uint64_t gpu_va)
{
    struct kbase_ioctl_mem_free f = { .gpu_addr = gpu_va };
    return mali_ioctl(fd, KBASE_IOCTL_MEM_FREE, &f, "MEM_FREE");
}

static inline void *p0_map(int fd, uint64_t gpu_va, size_t pages)
{
    return mmap(NULL, pages * PAGE_SIZE, PROT_READ | PROT_WRITE,
                MAP_SHARED, fd, (off_t)gpu_va);
}

static inline int p0_group_create(int fd, uint8_t *handle)
{
    union kbase_ioctl_cs_queue_group_create g = {0};
    g.in.tiler_mask = ~0ULL;
    g.in.fragment_mask = ~0ULL;
    g.in.compute_mask = ~0ULL;
    g.in.cs_min = 1;
    g.in.priority = 0;
    g.in.tiler_max = 1;
    g.in.fragment_max = 1;
    g.in.compute_max = 1;
    g.in.csi_handlers = 0;
    g.in.reserved = 0;
    if (mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_GROUP_CREATE, &g, "CS_QUEUE_GROUP_CREATE") < 0)
        return -1;
    *handle = g.out.group_handle;
    return 0;
}

static inline int p0_group_term(int fd, uint8_t handle)
{
    struct kbase_ioctl_cs_queue_group_term t = {0};
    t.group_handle = handle;
    return mali_ioctl(fd, KBASE_IOCTL_CS_QUEUE_GROUP_TERMINATE, &t, "CS_QUEUE_GROUP_TERMINATE");
}

#endif
