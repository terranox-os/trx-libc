#ifndef _UNISTD_H
#define _UNISTD_H

#ifdef __cplusplus
extern "C" {
#endif

typedef long ssize_t;
typedef unsigned long size_t;
typedef long off_t;

/* sysconf name constants */
#define _SC_PAGE_SIZE 30

ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
int close(int fd);
off_t lseek(int fd, off_t offset, int whence);
int unlink(const char *path);
int getpid(void);
int dup2(int oldfd, int newfd);
int pipe(int pipefd[2]);
long sysconf(int name);
void _exit(int status) __attribute__((noreturn));

/* lseek whence constants */
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

#ifdef __cplusplus
}
#endif

#endif /* _UNISTD_H */
