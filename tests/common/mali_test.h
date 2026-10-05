#ifndef MALI_TEST_H
#define MALI_TEST_H

#include <stdint.h>
#include <stddef.h>

/*
 * mali_open() opens /dev/mali0 and completes the mandatory U/K handshake
 * (KBASE_IOCTL_VERSION_CHECK then KBASE_IOCTL_SET_FLAGS). Without it every
 * other ioctl returns -EPERM, because no kbase context exists yet.
 *
 * Returns a ready-to-use fd, or -1. On -1, mali_open_reason() explains why
 * (device missing vs. handshake/version failure) so a caller can skip for a
 * backend reason rather than reporting a spurious test failure.
 */
int mali_open(void);
const char *mali_open_reason(void);
void mali_close(int fd);
int mali_ioctl(int fd, unsigned long request, void *arg, const char *op);
int test_ok(const char *name);
int test_fail(const char *name, const char *why);
int test_skip(const char *name, const char *why);
void test_errno_detail(char *buf, size_t n, const char *op);

#endif
