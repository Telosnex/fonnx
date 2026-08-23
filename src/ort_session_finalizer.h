#ifndef FONNX_ORT_SESSION_FINALIZER_H_
#define FONNX_ORT_SESSION_FINALIZER_H_

#include <stdint.h>

#if defined(_WIN32)
#define FONNX_EXPORT __declspec(dllexport)
#else
#define FONNX_EXPORT __attribute__((visibility("default")))
#endif

#define FONNX_ORT_SESSION_FINALIZER_ABI_VERSION 1u

typedef void (*fonnx_release_fn)(void *);

typedef struct fonnx_ort_session_context {
  void **session;
  void **env;
  fonnx_release_fn release_session;
  fonnx_release_fn release_env;
} fonnx_ort_session_context;

FONNX_EXPORT uint32_t fonnx_ort_session_finalizer_abi_version(void);
FONNX_EXPORT const char *fonnx_ort_session_finalizer_build_info(void);
FONNX_EXPORT void fonnx_release_ort_session_context(void *opaque);

#endif  // FONNX_ORT_SESSION_FINALIZER_H_
