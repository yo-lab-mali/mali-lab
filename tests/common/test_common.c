#include "mali_test.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int mali_open(void) { return open("/dev/mali0", O_RDWR | O_CLOEXEC); }
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
