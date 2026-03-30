#ifndef _NETINET_IN_H
#define _NETINET_IN_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned short in_port_t;
typedef unsigned int   in_addr_t;

#define INADDR_ANY       ((in_addr_t)0x00000000)
#define INADDR_LOOPBACK  ((in_addr_t)0x7F000001)
#define INADDR_BROADCAST ((in_addr_t)0xFFFFFFFF)

struct in_addr {
    in_addr_t s_addr;
};

struct sockaddr_in {
    unsigned short sin_family;
    in_port_t      sin_port;    /* network byte order */
    struct in_addr sin_addr;    /* network byte order */
    unsigned char  sin_zero[8];
};

/* Byte-order conversion */
unsigned short htons(unsigned short x);
unsigned int   htonl(unsigned int x);
unsigned short ntohs(unsigned short x);
unsigned int   ntohl(unsigned int x);

#ifdef __cplusplus
}
#endif

#endif /* _NETINET_IN_H */
