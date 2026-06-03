#include "libraw_bridge.h"

#include <algorithm>
#include <cstring>
#include <limits>
#include <new>
#include <string>

#include <libraw/libraw.h>

static constexpr int32_t kMaxDimension = 16384;
static constexpr int64_t kMaxPixels = 120000000;

static void write_error(char* buffer, int32_t length, const std::string& message) {
  if (!buffer || length <= 0) return;
  const auto n = std::min<int32_t>(static_cast<int32_t>(message.size()), length - 1);
  std::memcpy(buffer, message.data(), n);
  buffer[n] = '\0';
}

int32_t aqua_decode_raw_to_rgba8(const char* input_path, AquaRawImage* output, char* error_buffer, int32_t error_buffer_length) {
  if (!input_path || !output) {
    write_error(error_buffer, error_buffer_length, "input_path and output are required");
    return -1;
  }

  output->rgba = nullptr;
  output->width = 0;
  output->height = 0;
  output->stride = 0;

  LibRaw raw;
  raw.imgdata.params.output_bps = 8;
  raw.imgdata.params.gamm[0] = 1.0;
  raw.imgdata.params.gamm[1] = 1.0;
  raw.imgdata.params.use_camera_wb = 1;
  raw.imgdata.params.no_auto_bright = 1;
  raw.imgdata.params.output_color = 1;  // sRGB

  int rc = raw.open_file(input_path);
  if (rc != LIBRAW_SUCCESS) {
    write_error(error_buffer, error_buffer_length, libraw_strerror(rc));
    return rc;
  }
  rc = raw.unpack();
  if (rc != LIBRAW_SUCCESS) {
    write_error(error_buffer, error_buffer_length, libraw_strerror(rc));
    return rc;
  }
  rc = raw.dcraw_process();
  if (rc != LIBRAW_SUCCESS) {
    write_error(error_buffer, error_buffer_length, libraw_strerror(rc));
    return rc;
  }

  libraw_processed_image_t* image = raw.dcraw_make_mem_image(&rc);
  if (!image || rc != LIBRAW_SUCCESS) {
    write_error(error_buffer, error_buffer_length, image ? libraw_strerror(rc) : "dcraw_make_mem_image failed");
    if (image) LibRaw::dcraw_clear_mem(image);
    return rc == LIBRAW_SUCCESS ? -2 : rc;
  }
  if (image->colors < 3 || image->bits != 8) {
    LibRaw::dcraw_clear_mem(image);
    write_error(error_buffer, error_buffer_length, "expected 8-bit RGB output from LibRaw");
    return -3;
  }

  const int32_t width = static_cast<int32_t>(image->width);
  const int32_t height = static_cast<int32_t>(image->height);
  if (width <= 0 || height <= 0 || width > kMaxDimension || height > kMaxDimension || static_cast<int64_t>(width) * height > kMaxPixels) {
    LibRaw::dcraw_clear_mem(image);
    write_error(error_buffer, error_buffer_length, "decoded RAW dimensions exceed safe processing limits");
    return -5;
  }
  if (width > std::numeric_limits<int32_t>::max() / 4) {
    LibRaw::dcraw_clear_mem(image);
    write_error(error_buffer, error_buffer_length, "decoded RAW row stride overflow");
    return -6;
  }

  const int32_t stride = width * 4;
  const size_t allocation_size = static_cast<size_t>(stride) * static_cast<size_t>(height);
  auto* rgba = new (std::nothrow) uint8_t[allocation_size];
  if (!rgba) {
    LibRaw::dcraw_clear_mem(image);
    write_error(error_buffer, error_buffer_length, "out of memory");
    return -4;
  }

  const uint8_t* src = image->data;
  for (int32_t y = 0; y < height; ++y) {
    for (int32_t x = 0; x < width; ++x) {
      const auto srcIndex = static_cast<size_t>((y * width + x) * image->colors);
      const auto dstIndex = static_cast<size_t>(y * stride + x * 4);
      rgba[dstIndex + 0] = src[srcIndex + 0];
      rgba[dstIndex + 1] = src[srcIndex + 1];
      rgba[dstIndex + 2] = src[srcIndex + 2];
      rgba[dstIndex + 3] = 255;
    }
  }

  output->rgba = rgba;
  output->width = width;
  output->height = height;
  output->stride = stride;
  LibRaw::dcraw_clear_mem(image);
  return 0;
}

void aqua_free_raw_image(AquaRawImage* image) {
  if (!image) return;
  delete[] image->rgba;
  image->rgba = nullptr;
  image->width = 0;
  image->height = 0;
  image->stride = 0;
}
