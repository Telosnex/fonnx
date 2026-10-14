#include "onnxruntime_c_api.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#endif

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "CHECK failed at %s:%d: %s\n", __FILE__, __LINE__,      \
              #condition);                                                     \
      exit(1);                                                                 \
    }                                                                          \
  } while (0)

static const OrtApi *ort;

static void check_status(OrtStatus *status, const char *operation) {
  if (status == NULL) return;
  fprintf(stderr, "%s failed: %s\n", operation, ort->GetErrorMessage(status));
  ort->ReleaseStatus(status);
  exit(1);
}

#ifdef _WIN32
static const ORTCHAR_T *model_path(const char *utf8, wchar_t *buffer,
                                    size_t length) {
  int result = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1,
                                   buffer, (int)length);
  CHECK(result > 0);
  return buffer;
}
#else
static const ORTCHAR_T *model_path(const char *utf8, char *buffer,
                                    size_t length) {
  (void)buffer;
  (void)length;
  return utf8;
}
#endif

static void create_session(OrtEnv *env, const char *path) {
  OrtSessionOptions *options = NULL;
  OrtSession *session = NULL;
#ifdef _WIN32
  wchar_t native_path[4096];
#else
  char native_path[1];
#endif
  check_status(ort->CreateSessionOptions(&options), "CreateSessionOptions");
  check_status(ort->CreateSession(env, model_path(path, native_path, 4096),
                                  options, &session),
               "CreateSession");
  CHECK(session != NULL);
  ort->ReleaseSession(session);
  ort->ReleaseSessionOptions(options);
}

int main(int argc, char **argv) {
  CHECK(argc == 2);
  const OrtApiBase *base = OrtGetApiBase();
  CHECK(base != NULL && base->GetApi != NULL && base->GetVersionString != NULL);
  ort = base->GetApi(ORT_API_VERSION);
  CHECK(ort != NULL);
  CHECK(strncmp(base->GetVersionString(), "1.27.", 5) == 0);

  OrtEnv *env = NULL;
  check_status(ort->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "fonnx-runtime-smoke", &env),
               "CreateEnv");
  CHECK(env != NULL);
  create_session(env, argv[1]);
  ort->ReleaseEnv(env);
  printf("  ORT %s identity session\n", base->GetVersionString());
  printf("PASS: exact ONNX Runtime artifacts\n");
  return 0;
}
