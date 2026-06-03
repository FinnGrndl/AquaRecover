#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AquaRawImage {
  uint8_t* rgba;
  int32_t width;
  int32_t height;
  int32_t stride;
} AquaRawImage;

int32_t aqua_decode_raw_to_rgba8(const char* input_path, AquaRawImage* output, char* error_buffer, int32_t error_buffer_length);
void aqua_free_raw_image(AquaRawImage* image);

#ifdef __cplusplus
}
#endif
