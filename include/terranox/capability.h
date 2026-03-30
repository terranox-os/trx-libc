#ifndef _TERRANOX_CAPABILITY_H
#define _TERRANOX_CAPABILITY_H

#ifdef __cplusplus
extern "C" {
#endif

typedef long long          trx_pid_t;
typedef unsigned long long trx_cap_id_t;
typedef unsigned long long trx_rights_t;
typedef unsigned int       trx_count_t;

int trx_cap_grant(trx_pid_t pid, trx_cap_id_t cap_id, trx_rights_t rights);
int trx_cap_revoke(trx_pid_t pid, trx_cap_id_t cap_id);
int trx_cap_query(trx_pid_t pid, void *caps, trx_count_t *count);

#ifdef __cplusplus
}
#endif

#endif /* _TERRANOX_CAPABILITY_H */
