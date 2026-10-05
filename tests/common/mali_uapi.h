#ifndef MALI_UAPI_ADAPTER_H
#define MALI_UAPI_ADAPTER_H

/*
 * Compile against the exact r54p0 UAPI supplied with the integrated Arm tree.
 * No ioctl number or structure is reconstructed here.
 */
#include <uapi/gpu/arm/midgard/mali_kbase_ioctl.h>
#include <uapi/gpu/arm/midgard/mali_base_common_kernel.h>
#if defined(__has_include)
# if __has_include(<uapi/gpu/arm/midgard/csf/mali_base_csf_kernel.h>)
#  include <uapi/gpu/arm/midgard/csf/mali_base_csf_kernel.h>
# endif
# if __has_include(<uapi/gpu/arm/midgard/csf/mali_kbase_csf_ioctl.h>)
#  include <uapi/gpu/arm/midgard/csf/mali_kbase_csf_ioctl.h>
# endif
#endif

#ifndef BASEP_QUEUE_NR_MMAP_USER_PAGES
#define BASEP_QUEUE_NR_MMAP_USER_PAGES 3
#endif

#ifndef PAGE_SIZE
#define PAGE_SIZE 4096UL
#endif

#endif
