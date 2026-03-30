#ifndef _STDLIB_H
#define _STDLIB_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned long size_t;

#define RAND_MAX 0x7FFFFFFF

int   atoi(const char *s);
int   abs(int x);
long  labs(long x);

void  srand(unsigned int seed);
int   rand(void);

void *bsearch(const void *key, const void *base, size_t nmemb, size_t size,
              int (*compar)(const void *, const void *));
void  qsort(void *base, size_t nmemb, size_t size,
            int (*compar)(const void *, const void *));

#ifdef __cplusplus
}
#endif

#endif /* _STDLIB_H */
