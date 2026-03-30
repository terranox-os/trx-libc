#ifndef _ARPA_INET_H
#define _ARPA_INET_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned int socklen_t;

/* Address conversion */
int inet_pton(int af, const char *src, void *dst);
const char *inet_ntop(int af, const void *src, char *dst, socklen_t size);

/* Byte-order conversion (also declared in netinet/in.h) */
unsigned short htons(unsigned short x);
unsigned int   htonl(unsigned int x);
unsigned short ntohs(unsigned short x);
unsigned int   ntohl(unsigned int x);

#ifdef __cplusplus
}
#endif

#endif /* _ARPA_INET_H */
