#include "mali_test.h"
#include "mali_uapi.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static char mali_open_error[192];

const char *mali_open_reason(void)
{
    return mali_open_error[0] ? mali_open_error : "unspecified failure";
}

/*
 * Kbase gates the ioctl surface. Until setup_state reaches
 * KBASE_FILE_COMPLETE, kbase_ioctl() falls through
 * kbase_file_get_kctx_if_setup_complete() and every "normal" ioctl
 * (MEM_ALLOC, CS_QUEUE_*, ...) returns -EPERM rather than -ENOTTY.
 *
 * The only ordering that completes setup is:
 *   1. KBASE_IOCTL_VERSION_CHECK  - negotiate U/K version (1.<minor>)
 *   2. KBASE_IOCTL_SET_FLAGS      - create the kbase context
 *
 * Both must succeed before any other ioctl is meaningful, so the handshake
 * is part of opening the device rather than something each test repeats.
 *
 * From kbase_api_handshake(): if the requested major matches, minor is
 * clamped down to the driver's BASE_UK_VERSION_MINOR, so the kernel's
 * answer is authoritative and must be read back before continuing.
 */
static int mali_handshake(int fd)
{
    struct kbase_ioctl_version_check version = {
        .major = BASE_UK_VERSION_MAJOR,
        .minor = BASE_UK_VERSION_MINOR,
    };
    struct kbase_ioctl_set_flags flags = {
        .create_flags = BASE_CONTEXT_CREATE_FLAG_NONE,
    };

    if (ioctl(fd, KBASE_IOCTL_VERSION_CHECK, &version) < 0) {
        snprintf(mali_open_error, sizeof(mali_open_error),
                 "KBASE_IOCTL_VERSION_CHECK failed: errno=%d (%s)", errno,
                 strerror(errno));
        return -1;
    }
    if (version.major != BASE_UK_VERSION_MAJOR) {
        snprintf(mali_open_error, sizeof(mali_open_error),
                 "U/K version mismatch: driver offers %u.%u, tests built for %d.%d",
                 version.major, version.minor, BASE_UK_VERSION_MAJOR,
                 BASE_UK_VERSION_MINOR);
        return -1;
    }

    if (ioctl(fd, KBASE_IOCTL_SET_FLAGS, &flags) < 0) {
        snprintf(mali_open_error, sizeof(mali_open_error),
                 "KBASE_IOCTL_SET_FLAGS failed: errno=%d (%s)", errno,
                 strerror(errno));
        return -1;
    }
    return 0;
}

int mali_open(void)
{
    int fd;

    mali_open_error[0] = '\0';
    fd = open("/dev/mali0", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        snprintf(mali_open_error, sizeof(mali_open_error),
                 "/dev/mali0 unavailable: errno=%d (%s)", errno, strerror(errno));
        return -1;
    }
    if (mali_handshake(fd) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

void mali_close(int fd) { if (fd >= 0) close(fd); }

int mali_ioctl(int fd, unsigned long request, void *arg, const char *op)
{
    int rc = ioctl(fd, request, arg);
    if (rc < 0) {
        fprintf(stderr, "[IOCTL] %s: rc=%d errno=%d (%s)\n",
                op, rc, errno, strerror(errno));
    }
    return rc;
}

void test_errno_detail(char *buf, size_t n, const char *op)
{
    if (n) snprintf(buf, n, "%s: errno=%d (%s)", op, errno, strerror(errno));
}

int test_ok(const char *name) { printf("[PASS] %s\n", name); return 0; }
int test_fail(const char *name, const char *why)
{
    fprintf(stderr, "[FAIL] %s: %s\n", name, why);
    return 1;
}
int test_skip(const char *name, const char *why)
{
    printf("[SKIP] %s: %s\n", name, why);
    return 77;
}
