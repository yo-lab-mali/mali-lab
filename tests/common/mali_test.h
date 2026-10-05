#ifndef MALI_TEST_H
#define MALI_TEST_H

#include <stdint.h>
#include <stddef.h>

int mali_open(void);
void mali_close(int fd);
int mali_ioctl(int fd, unsigned long request, void *arg, const char *op);
int test_ok(const char *name);
int test_fail(const char *name, const char *why);
int test_skip(const char *name, const char *why);
void test_errno_detail(char *buf, size_t n, const char *op);

#endif
