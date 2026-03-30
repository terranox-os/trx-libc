#ifndef _ERRNO_H
#define _ERRNO_H

#ifdef __cplusplus
extern "C" {
#endif

int *__errno_location(void);
#define errno (*__errno_location())

#define EPERM       1
#define ENOENT      2
#define ESRCH       3
#define EINTR       4
#define EIO         5
#define EBADF       9
#define EAGAIN      11
#define ENOMEM      12
#define EACCES      13
#define EFAULT      14
#define EBUSY       16
#define EEXIST      17
#define EINVAL      22
#define EPIPE       32
#define ENOSYS      38
#define ETIMEDOUT   110

#ifdef __cplusplus
}
#endif

#endif /* _ERRNO_H */
