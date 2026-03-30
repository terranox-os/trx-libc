#ifndef _TERRANOX_INPUT_H
#define _TERRANOX_INPUT_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned int trx_count_t;
typedef long long    trx_handle_t;

int trx_input_enumerate(void *devices, trx_count_t *count);
trx_handle_t trx_input_open(unsigned int dev_id, unsigned int flags);
int trx_input_close(trx_handle_t handle);
trx_handle_t trx_input_read_events(trx_handle_t handle, void *events, unsigned int max);
int trx_input_grab(trx_handle_t handle);
int trx_input_ungrab(trx_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* _TERRANOX_INPUT_H */
