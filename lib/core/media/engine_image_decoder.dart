import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decoded 8-bit RGBA pixels of a downsized photo.
typedef RgbaThumbnail = ({Uint8List rgba, int width, int height});

/// Decodes [path] through the engine codec at no more than [maxDimension]
/// on the long side. The engine reads every format the platform can show,
/// HEIC on Apple platforms included, and decodes straight to the target size.
Future<RgbaThumbnail?> decodeRgbaThumbnail(
  String path,
  int maxDimension,
) async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final ui.Codec codec;
  try {
    // The codec takes ownership of the buffer once it exists.
    codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final longSide = math.max(width, height);
        if (longSide <= maxDimension) {
          return ui.TargetImageSize(width: width, height: height);
        }
        final scale = maxDimension / longSide;
        return ui.TargetImageSize(
          width: math.max(1, (width * scale).round()),
          height: math.max(1, (height * scale).round()),
        );
      },
    );
  } on Object {
    buffer.dispose();
    rethrow;
  }
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return (
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}
