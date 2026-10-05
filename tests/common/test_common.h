#ifndef MALI_TEST_H
#define MALI_TEST_H
#include <stdint.h>
int mali_open(void);
void mali_close(int fd);
int test_ok(const char *name);
int test_fail(const char *name, const char *why);
#endif
