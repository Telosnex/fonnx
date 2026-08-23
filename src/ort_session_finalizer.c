#include <stdint.h>

#if defined(_WIN32)
#include <objbase.h>
#define FONNX_EXPORT __declspec(dllexport)
#define fonnx_dart_free CoTaskMemFree
#else
#include <stdlib.h>
#define FONNX_EXPORT __attribute__((visibility("default")))
#define fonnx_dart_free free
#endif

typedef void (*fonnx_release_fn)(void *);

typedef struct fonnx_ort_session_context {
  void **session;
  void **env;
  fonnx_release_fn release_session;
  fonnx_release_fn release_env;
} fonnx_ort_session_context;

FONNX_EXPORT void fonnx_release_ort_session_context(void *opaque) {
  fonnx_ort_session_context *context =
      (fonnx_ort_session_context *)opaque;
  if (context == NULL) return;

  if (context->session != NULL) {
    if (*context->session != NULL && context->release_session != NULL) {
      context->release_session(*context->session);
      *context->session = NULL;
    }
    fonnx_dart_free(context->session);
    context->session = NULL;
  }

  if (context->env != NULL) {
    if (*context->env != NULL && context->release_env != NULL) {
      context->release_env(*context->env);
      *context->env = NULL;
    }
    fonnx_dart_free(context->env);
    context->env = NULL;
  }

  fonnx_dart_free(context);
}
