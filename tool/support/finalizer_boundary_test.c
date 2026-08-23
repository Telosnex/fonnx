#include "ort_session_finalizer.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "CHECK failed at %s:%d: %s\n", __FILE__, __LINE__,      \
              #condition);                                                     \
      exit(1);                                                                 \
    }                                                                          \
  } while (0)

typedef struct fake_ort_object {
  uint32_t marker;
  uint32_t serial;
} fake_ort_object;

static uint32_t release_count;
static uint64_t released_serial_sum;

static void release_fake(void *opaque) {
  fake_ort_object *object = (fake_ort_object *)opaque;
  CHECK(object != NULL && object->marker == 0xf077cafeu);
  release_count++;
  released_serial_sum += object->serial;
  object->marker = 0;
  free(object);
}

static uint32_t next_random(uint32_t *state) {
  *state ^= *state << 13;
  *state ^= *state >> 17;
  *state ^= *state << 5;
  return *state;
}

static fake_ort_object *new_object(uint32_t serial) {
  fake_ort_object *object = (fake_ort_object *)malloc(sizeof(*object));
  CHECK(object != NULL);
  object->marker = 0xf077cafeu;
  object->serial = serial;
  return object;
}

int main(void) {
  CHECK(fonnx_ort_session_finalizer_abi_version() ==
        FONNX_ORT_SESSION_FINALIZER_ABI_VERSION);
  CHECK(strcmp(fonnx_ort_session_finalizer_build_info(),
               "fonnx ORT session finalizer ABI 1") == 0);
  fonnx_release_ort_session_context(NULL);

  uint32_t state = 0x46f06e6eu;
  uint32_t expected_release_count = 0;
  uint64_t expected_serial_sum = 0;
  for (uint32_t iteration = 0; iteration < 8192; iteration++) {
    fonnx_ort_session_context *context =
        (fonnx_ort_session_context *)calloc(1, sizeof(*context));
    CHECK(context != NULL);

    fake_ort_object *unowned_session = NULL;
    fake_ort_object *unowned_env = NULL;
    if ((next_random(&state) & 1u) != 0) {
      context->session = (void **)calloc(1, sizeof(void *));
      CHECK(context->session != NULL);
      if ((next_random(&state) & 1u) != 0) {
        fake_ort_object *object = new_object(iteration * 2);
        *context->session = object;
        if ((next_random(&state) & 1u) != 0) {
          context->release_session = release_fake;
          expected_release_count++;
          expected_serial_sum += object->serial;
        } else {
          unowned_session = object;
        }
      }
    }
    if ((next_random(&state) & 1u) != 0) {
      context->env = (void **)calloc(1, sizeof(void *));
      CHECK(context->env != NULL);
      if ((next_random(&state) & 1u) != 0) {
        fake_ort_object *object = new_object(iteration * 2 + 1);
        *context->env = object;
        if ((next_random(&state) & 1u) != 0) {
          context->release_env = release_fake;
          expected_release_count++;
          expected_serial_sum += object->serial;
        } else {
          unowned_env = object;
        }
      }
    }

    fonnx_release_ort_session_context(context);
    if (unowned_session != NULL) free(unowned_session);
    if (unowned_env != NULL) free(unowned_env);
  }

  CHECK(release_count == expected_release_count);
  CHECK(released_serial_sum == expected_serial_sum);
  printf("  finalizer ownership corpus: 8192 deterministic partial contexts\n");
  printf("PASS: fonnx finalizer ABI boundary suite\n");
  return 0;
}
