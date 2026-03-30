#ifndef _TERRANOX_IPC_H
#define _TERRANOX_IPC_H

#ifdef __cplusplus
extern "C" {
#endif

typedef long long trx_handle_t;

/* Channel IPC */
int trx_channel_create(unsigned int flags, trx_handle_t *ep0, trx_handle_t *ep1);
int trx_channel_send(trx_handle_t ep, const unsigned char *data, unsigned long len);
trx_handle_t trx_channel_recv(trx_handle_t ep, unsigned char *buf, unsigned long buf_len);
int trx_channel_close(trx_handle_t ep);

/* Kernel signal objects */
trx_handle_t trx_signal_create(unsigned int flags);
int trx_signal_raise(trx_handle_t handle, unsigned int bits);
trx_handle_t trx_signal_wait(trx_handle_t handle, unsigned int mask, long long timeout_ns);

#ifdef __cplusplus
}
#endif

#endif /* _TERRANOX_IPC_H */
