#ifndef _FCNTL_H
#define _FCNTL_H

#ifdef __cplusplus
extern "C" {
#endif

/* O_* file access mode flags */
#define O_RDONLY  0
#define O_WRONLY  1
#define O_RDWR   2

/* O_* file creation / status flags */
#define O_CREAT   0100
#define O_EXCL    0200
#define O_TRUNC   01000
#define O_APPEND  02000

typedef unsigned int mode_t;

int open(const char *path, int flags, ...);

#ifdef __cplusplus
}
#endif

#endif /* _FCNTL_H */
