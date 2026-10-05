#include "../common/mali_test.h"
#include <stdio.h>
int main(void) {
    int fd = mali_open();
    if (fd < 0) { perror("/dev/mali0"); return test_fail("basic ioctl probe", "device unavailable"); }
    mali_close(fd);
    return test_ok("basic ioctl probe");
}
