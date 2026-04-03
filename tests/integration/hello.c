#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

int main(int argc, char **argv) {
    // Test 1: write to stdout
    const char *msg = "trx-libc: hello from TerranoxOS!\n";
    write(1, msg, strlen(msg));

    // Test 2: getpid
    int pid = getpid();

    // Test 3: malloc + free
    char *buf = (char *)malloc(64);
    if (buf) {
        strcpy(buf, "malloc works\n");
        write(1, buf, strlen(buf));
        free(buf);
    }

    // Test 4: errno
    int *ep = __errno_location();
    *ep = 0;

    // All tests passed
    const char *ok = "trx-libc: all integration tests passed\n";
    write(1, ok, strlen(ok));

    return 0;
}
