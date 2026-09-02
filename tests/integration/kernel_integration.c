/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * TerranoxOS kernel-facing libc integration suite.
 *
 * The test deliberately uses only the small freestanding libc surface so the
 * same ELF can be loaded by the kernel's run-trxlibc shell command.
 */

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <terranox/display.h>
#include <terranox/input.h>
#include <terranox/ipc.h>
#include <unistd.h>

static int failures;

static void check(const char *name, int ok) {
    const char *prefix = ok ? "[trx-libc] PASS " : "[trx-libc] FAIL ";
    write(2, prefix, strlen(prefix));
    write(2, name, strlen(name));
    write(2, "\n", 1);
    if (!ok) failures++;
}

static void test_file_io(void) {
    static const char path[] = "/tmp/trx-libc-e2e";
    static const char payload[] = "terranox libc integration";
    char buf[64];
    struct stat st;
    int fd = open(path, O_CREAT | O_RDWR, 0600);
    int ok = fd >= 0;

    if (ok) ok = write(fd, payload, strlen(payload)) == (long)strlen(payload);
    if (ok) ok = lseek(fd, 0, SEEK_SET) == 0;
    if (ok) {
        long n = read(fd, buf, sizeof(buf));
        ok = n == (long)strlen(payload) && memcmp(buf, payload, strlen(payload)) == 0;
    }
    if (ok) ok = fstat(fd, &st) == 0 && st.st_size == (long)strlen(payload);
    if (ok) ok = close(fd) == 0;
    if (ok) ok = stat(path, &st) == 0 && st.st_size == (long)strlen(payload) && S_ISREG(st.st_mode);
    if (fd >= 0) unlink(path);

    check("file-io", ok);
}

static void test_memory(void) {
    unsigned char *blocks[32];
    unsigned int sizes[32];
    int ok = 1;

    for (unsigned int i = 0; i < 32; i++) {
        blocks[i] = 0;
        sizes[i] = 17 + i * 31;
        blocks[i] = (unsigned char *)malloc(sizes[i]);
        if (!blocks[i]) {
            ok = 0;
            break;
        }
        memset(blocks[i], (int)i, sizes[i]);
    }

    if (ok) {
        for (unsigned int i = 0; i < 32; i++) {
            unsigned int new_size = sizes[i] + 113;
            unsigned char *grown = (unsigned char *)realloc(blocks[i], new_size);
            if (!grown) {
                ok = 0;
                break;
            }
            for (unsigned int j = 0; j < sizes[i]; j++) {
                if (grown[j] != (unsigned char)i) ok = 0;
            }
            blocks[i] = grown;
        }
    }

    for (unsigned int i = 0; i < 32; i++) free(blocks[i]);

    unsigned char *zeroed = (unsigned char *)calloc(64, 1);
    if (!zeroed) ok = 0;
    if (zeroed) {
        for (unsigned int i = 0; i < 64; i++) {
            if (zeroed[i] != 0) ok = 0;
        }
        free(zeroed);
    }

    check("memory", ok);
}

static pthread_mutex_t thread_mutex = PTHREAD_MUTEX_INITIALIZER;
static volatile int thread_ran;
static volatile int thread_trylock_result;

static void *thread_body(void *arg) {
    if (arg == (void *)&thread_ran) thread_ran = 1;
    thread_trylock_result = pthread_mutex_trylock(&thread_mutex);
    if (thread_trylock_result == 0) pthread_mutex_unlock(&thread_mutex);
    return 0;
}

static void test_threads(void) {
    pthread_t thread;
    int ok;

    thread_ran = 0;
    thread_trylock_result = 0;
    ok = pthread_mutex_lock(&thread_mutex) == 0;
    if (ok) ok = pthread_create(&thread, 0, thread_body, (void *)&thread_ran) == 0;
    if (ok) ok = pthread_join(thread, 0) == 0;
    if (ok) ok = thread_ran == 1 && thread_trylock_result == EBUSY;
    pthread_mutex_unlock(&thread_mutex);

    check("threads", ok);
}

struct display_info {
    unsigned int display_id;
    unsigned int width_px;
    unsigned int height_px;
    unsigned int refresh_mhz;
    unsigned int connector;
    char name[32];
    unsigned int pad0;
};

struct compositor_layer {
    long long surface_handle;
    int x;
    int y;
    unsigned int width;
    unsigned int height;
    int z_order;
    unsigned int flags;
};

static void test_display(void) {
    struct display_info displays[4];
    struct compositor_layer layer;
    trx_count_t count = 4;
    int ok = trx_display_enumerate(displays, &count) >= 1 && count >= 1;
    trx_handle_t compositor = -1;
    trx_handle_t surface = -1;

    if (ok) {
        ok = displays[0].width_px > 0 && displays[0].height_px > 0;
        compositor = trx_compositor_create(0);
        ok = ok && compositor >= 0;
    }
    if (ok) {
        surface = trx_surface_create(2, 2, 0, 0);
        ok = surface >= 0;
    }
    if (ok) {
        layer.surface_handle = surface;
        layer.x = 0;
        layer.y = 0;
        layer.width = 2;
        layer.height = 2;
        layer.z_order = 0;
        layer.flags = 1;
        ok = trx_compositor_present(compositor, &layer, 1) == 0;
    }
    if (surface >= 0) trx_surface_destroy(surface);

    /* The current surface ABI has no user mapping operation. Present success
     * validates the compositor/framebuffer path; pixel readback is separate. */
    check("display", ok);
}

struct input_device {
    unsigned int device_id;
    unsigned int type;
    char name[64];
};

struct input_event {
    unsigned long long timestamp_ns;
    unsigned int type;
    unsigned int code;
    int value;
    unsigned int device_id;
};

static void test_input(void) {
    struct input_device devices[4];
    struct input_event events[8];
    trx_count_t count = 4;
    int ok = trx_input_enumerate(devices, &count) >= 1 && count >= 1;
    trx_handle_t input = -1;

    if (ok) {
        input = trx_input_open(devices[0].device_id, 0);
        ok = input >= 0;
    }
    if (ok) ok = trx_input_read_events(input, events, 8) >= 0;
    if (input >= 0) ok = trx_input_close(input) == 0 && ok;

    check("input", ok);
}

static void signal_handler(int sig) {
    (void)sig;
}

static void test_signals(void) {
    struct sigaction_t act = {0};
    struct sigaction_t old = {0};
    struct sigaction_t after = {0};
    struct sigaction_t reset = {0};
    int ok;

    act.handler = signal_handler;
    ok = sigaction(SIGUSR1, &act, &old) == 0;
    if (ok) ok = kill(getpid(), 0) == 0;
    if (ok) ok = raise(SIGUSR1) == 0;
    if (ok) ok = sigaction(SIGUSR1, 0, &after) == 0 && after.handler == signal_handler;
    sigaction(SIGUSR1, &reset, 0);

    check("signals", ok);
}

static void test_ipc(void) {
    trx_handle_t endpoint0 = -1;
    trx_handle_t endpoint1 = -1;
    unsigned char sent[] = {'i', 'p', 'c'};
    unsigned char received[8];
    int ok = trx_channel_create(0, &endpoint0, &endpoint1) == 0;

    if (ok) ok = trx_channel_send(endpoint0, sent, 3) == 0;
    if (ok) {
        trx_handle_t n = trx_channel_recv(endpoint1, received, sizeof(received));
        ok = n == 3 && memcmp(received, sent, 3) == 0;
    }
    if (endpoint0 >= 0) trx_channel_close(endpoint0);
    if (endpoint1 >= 0) trx_channel_close(endpoint1);

    check("ipc", ok);
}

int main(void) {
    test_file_io();
    test_memory();
    test_threads();
    test_display();
    test_input();
    test_signals();
    test_ipc();

    if (failures == 0) {
        write(2, "[trx-libc] ALL PASSED\n", 22);
        return 0;
    }
    write(2, "[trx-libc] FAILED\n", 19);
    return 1;
}
