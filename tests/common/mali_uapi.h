#ifndef MALI_UAPI_ADAPTER_H
#define MALI_UAPI_ADAPTER_H

/*
 * Compile against the exact r54p0 UAPI supplied with the integrated Arm tree.
 * No ioctl number, structure size or constant is reconstructed here.
 *
 * Include order is load-bearing and is not obvious from the header names:
 *
 *  - <stddef.h> and <linux/types.h> first. The CSF UAPI spells
 *    BASEP_QUEUE_NR_MMAP_USER_PAGES as ((size_t)3), so size_t must be in scope
 *    before that header is read.
 *  - mali_base_kernel.h before mali_base_common_kernel.h. The latter pulls in
 *    mali_kbase_mem_flags.h, whose BASE_MEM_* flags are cast to
 *    base_mem_alloc_flags -- a typedef that only mali_base_kernel.h declares.
 *    The r54p0 UAPI is not self-contained in this respect and fails to compile
 *    with base_mem_alloc_flags undeclared.
 *  - mali_kbase_ioctl.h last. It defines KBASE_IOCTL_TYPE and the core ioctl
 *    numbers, and it includes csf/mali_kbase_csf_ioctl.h itself. The CSF ioctl
 *    macros reference KBASE_IOCTL_TYPE, which is only fine because macro
 *    expansion is lazy -- the CSF header is parsed before KBASE_IOCTL_TYPE
 *    exists and the name is resolved at each use.
 *
 * These includes are deliberately unconditional. An earlier version guarded the
 * CSF headers with __has_include and supplied a hardcoded fallback for
 * BASEP_QUEUE_NR_MMAP_USER_PAGES, which meant a tree missing the CSF UAPI
 * silently compiled against a locally guessed constant instead of failing.
 * scripts/configure-abi-check.sh already requires the CSF header to be present.
 */
#include <stddef.h>
#include <stdint.h>
#include <linux/types.h>
#include <linux/ioctl.h>

#include <uapi/gpu/arm/midgard/mali_base_kernel.h>
#include <uapi/gpu/arm/midgard/mali_base_common_kernel.h>
#include <uapi/gpu/arm/midgard/csf/mali_base_csf_kernel.h>
#include <uapi/gpu/arm/midgard/mali_kbase_ioctl.h>

/*
 * The r54p0 UAPI assumes PAGE_SIZE is already provided by the including
 * translation unit (Linux kernel sources get it from <linux/mm.h>). Tests are
 * built against libc headers, so supply it if absent.
 */
#ifndef PAGE_SIZE
#define PAGE_SIZE 4096UL
#endif

#endif
