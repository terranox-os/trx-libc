#ifndef _STDIO_H
#define _STDIO_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned long size_t;

/* Opaque FILE type — internal layout managed by Zig implementation */
typedef struct __FILE FILE;

/* Standard constants */
#define BUFSIZ  4096
#define EOF     (-1)

#ifndef NULL
#define NULL    ((void *)0)
#endif

/* Standard streams */
extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

/* Core I/O functions */
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
int    fflush(FILE *stream);
int    fputc(int c, FILE *stream);
int    fputs(const char *s, FILE *stream);
int    fgetc(FILE *stream);
int    puts(const char *s);
int    putchar(int c);

/* Error / EOF */
int    ferror(FILE *stream);
int    feof(FILE *stream);
void   clearerr(FILE *stream);

/* printf family */
int    fprintf(FILE *stream, const char *fmt, ...);
int    printf(const char *fmt, ...);
int    snprintf(char *buf, size_t size, const char *fmt, ...);

/* va_list variants (requires <stdarg.h>) */
#ifdef __GNUC__
int    vfprintf(FILE *stream, const char *fmt, __builtin_va_list ap);
int    vsnprintf(char *buf, size_t size, const char *fmt, __builtin_va_list ap);
#endif

/* fopen/fclose/fseek/ftell - Phase 2 (requires malloc) */
FILE *fopen(const char *path, const char *mode);
int   fclose(FILE *stream);
int   fseek(FILE *stream, long offset, int whence);
long  ftell(FILE *stream);

#ifdef __cplusplus
}
#endif

#endif /* _STDIO_H */
