#ifndef _TERRANOX_GPU_H
#define _TERRANOX_GPU_H

#ifdef __cplusplus
extern "C" {
#endif

typedef long long          trx_handle_t;
typedef unsigned long long trx_size_t;

trx_handle_t trx_gpu_open(unsigned int dev_id);
int trx_gpu_close(trx_handle_t handle);
unsigned int trx_gpu_alloc_bo(trx_handle_t handle, trx_size_t size, unsigned int flags);
int trx_gpu_free_bo(trx_handle_t handle, unsigned int bo_handle);
trx_handle_t trx_gpu_submit(trx_handle_t handle, const unsigned char *cmdbuf,
                            unsigned long len);
int trx_gpu_wait_fence(trx_handle_t fence, long long timeout_ns);

#ifdef __cplusplus
}
#endif

#endif /* _TERRANOX_GPU_H */
