#ifndef _SIGNAL_H
#define _SIGNAL_H

#ifdef __cplusplus
extern "C" {
#endif

typedef long long sigset_t;

typedef void (*sighandler_t)(int);

#define SIG_DFL ((sighandler_t)0)
#define SIG_IGN ((sighandler_t)1)

/* Signal numbers */
#define SIGHUP    1
#define SIGINT    2
#define SIGQUIT   3
#define SIGILL    4
#define SIGTRAP   5
#define SIGABRT   6
#define SIGBUS    7
#define SIGFPE    8
#define SIGKILL   9
#define SIGUSR1  10
#define SIGSEGV  11
#define SIGUSR2  12
#define SIGPIPE  13
#define SIGALRM  14
#define SIGTERM  15
#define SIGCHLD  17
#define SIGCONT  18
#define SIGSTOP  19
#define _NSIG    32

struct sigaction_t {
    sighandler_t handler;
    sigset_t     mask;
    int          flags;
    unsigned char _pad[24];
};

sighandler_t signal(int sig, sighandler_t handler);
int sigaction(int sig, const struct sigaction_t *act, struct sigaction_t *oldact);
int kill(int pid, int sig);
int raise(int sig);

int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int sig);
int sigdelset(sigset_t *set, int sig);
int sigismember(const sigset_t *set, int sig);

#ifdef __cplusplus
}
#endif

#endif /* _SIGNAL_H */
