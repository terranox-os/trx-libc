#ifndef _TERRANOX_DISPLAY_H
#define _TERRANOX_DISPLAY_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned int trx_count_t;
typedef long long    trx_handle_t;

/* Display enumeration and mode setting */
int trx_display_enumerate(void *displays, trx_count_t *count);
int trx_display_set_mode(unsigned int display_id, const void *mode);

/* Compositor */
trx_handle_t trx_compositor_create(unsigned int flags);
int trx_compositor_present(trx_handle_t handle, const void *layers, unsigned int count);

/* Surfaces */
trx_handle_t trx_surface_create(unsigned int width, unsigned int height,
                                unsigned int format, unsigned int flags);
int trx_surface_destroy(trx_handle_t handle);

/* GPU buffers */
trx_handle_t trx_buffer_create(unsigned int width, unsigned int height,
                               unsigned int format, unsigned int usage);
trx_handle_t trx_buffer_map(trx_handle_t handle, unsigned int prot);
int trx_buffer_unmap(trx_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* _TERRANOX_DISPLAY_H */
