#ifndef _PTHREAD_H
#define _PTHREAD_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned long size_t;

/* Thread ID type */
typedef unsigned long long pthread_t;

/* Mutex: 32 bytes (4-byte state + 28-byte padding) */
typedef struct {
    unsigned int state;
    unsigned char _pad[28];
} pthread_mutex_t;

/* Condition variable: 32 bytes (4-byte seq + 28-byte padding) */
typedef struct {
    unsigned int seq;
    unsigned char _pad[28];
} pthread_cond_t;

/* Thread attributes */
typedef struct {
    size_t stack_size;
    int    detach_state;
    unsigned char _pad[48];
} pthread_attr_t;

/* Thread-specific data key */
typedef unsigned int pthread_key_t;

/* Once control */
typedef unsigned int pthread_once_t;

/* Initializers */
#define PTHREAD_MUTEX_INITIALIZER  { 0, {0} }
#define PTHREAD_COND_INITIALIZER   { 0, {0} }
#define PTHREAD_ONCE_INIT          0

/* Maximum number of thread-specific data keys */
#define PTHREAD_KEYS_MAX 128

/* Mutex functions */
int pthread_mutex_init(pthread_mutex_t *mutex, const void *attr);
int pthread_mutex_lock(pthread_mutex_t *mutex);
int pthread_mutex_trylock(pthread_mutex_t *mutex);
int pthread_mutex_unlock(pthread_mutex_t *mutex);
int pthread_mutex_destroy(pthread_mutex_t *mutex);

/* Condition variable functions */
int pthread_cond_init(pthread_cond_t *cond, const void *attr);
int pthread_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex);
int pthread_cond_signal(pthread_cond_t *cond);
int pthread_cond_broadcast(pthread_cond_t *cond);
int pthread_cond_destroy(pthread_cond_t *cond);

/* Thread functions */
int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start_routine)(void *), void *arg);
int pthread_join(pthread_t thread, void **retval);
void pthread_exit(void *retval) __attribute__((noreturn));
pthread_t pthread_self(void);
int pthread_yield(void);

/* Thread-specific data */
int   pthread_key_create(pthread_key_t *key, void (*destructor)(void *));
int   pthread_key_delete(pthread_key_t key);
int   pthread_setspecific(pthread_key_t key, const void *value);
void *pthread_getspecific(pthread_key_t key);

/* Once */
int pthread_once(pthread_once_t *once_control, void (*init_routine)(void));

#ifdef __cplusplus
}
#endif

#endif /* _PTHREAD_H */
