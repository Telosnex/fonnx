#include "ort_session_finalizer.h"

#if defined(_WIN32)
#include <objbase.h>
#define fonnx_dart_free CoTaskMemFree
#else
#include <stdlib.h>
#define fonnx_dart_free free
#endif

FONNX_EXPORT uint32_t fonnx_ort_session_finalizer_abi_version(void) {
  return FONNX_ORT_SESSION_FINALIZER_ABI_VERSION;
}

FONNX_EXPORT const char *fonnx_ort_session_finalizer_build_info(void) {
  return "fonnx ORT session finalizer ABI 1";
}

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
