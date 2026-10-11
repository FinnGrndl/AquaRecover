import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/export_options.dart';
import '../models/image_transform_settings.dart';
import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import 'image_transform_service.dart';
import 'lut_service.dart';
import 'underwater_processor.dart';

/// The complete portable still pipeline: decode, restore, LUT, transform and
/// encode. It has no Flutter dependency, so the app's background isolates,
/// command-line tools and the MCP server all render through the same code.
class StillRenderPipeline {
  const StillRenderPipeline({
    this.processor = const UnderwaterProcessor(),
    this.lutService = const LutService(),
    this.transformService = const ImageTransformService(),
  });

  static const maxDecodedImagePixels = 120 * 1000 * 1000;
  static const maxDecodedImageDimension = 16384;

  final UnderwaterProcessor processor;
  final LutService lutService;
  final ImageTransformService transformService;

  /// Decodes [bytes] and validates the decoded size.
  img.Image decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image bytes.');
    }
    validateDecodedImage(decoded);
    return decoded;
  }

  static void validateDecodedImage(img.Image decoded) {
    if (decoded.width <= 0 || decoded.height <= 0) {
      throw const FormatException('Decoded image dimensions are invalid.');
    }
    if (decoded.width > maxDecodedImageDimension ||
        decoded.height > maxDecodedImageDimension ||
        decoded.width * decoded.height > maxDecodedImagePixels) {
      throw StateError(
        'Decoded image is too large for local processing '
        '(${decoded.width}x${decoded.height}).',
      );
    }
  }

  /// Renders [source] without encoding. [maxDimension] downsizes first, which
  /// is how previews keep their cost bounded.
  Future<img.Image> render(
    img.Image source, {
    required RestorationSettings settings,
    LutProfile lutProfile = LutProfile.none,
    ImageTransformSettings transform = const ImageTransformSettings(),
    RestorationRenderQuality quality = RestorationRenderQuality.export,
    int? maxDimension,
  }) async {
    final sized = maxDimension == null
        ? source
        : downscale(source, maxDimension);
    final restored = await processor.restoreImageInParallel(
      sized,
      settings,
      quality: quality,
    );
    final withLut = await lutService.apply(restored, lutProfile);
    return transformService.apply(withLut, transform);
  }

  /// Decodes, renders and encodes [bytes] according to [exportOptions].
  Future<Uint8List> renderEncoded(
    Uint8List bytes, {
    required RestorationSettings settings,
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
    ImageTransformSettings transform = const ImageTransformSettings(),
  }) async {
    final rendered = await render(
      decode(bytes),
      settings: settings,
      lutProfile: lutProfile,
      transform: transform,
    );
    return encode(
      rendered,
      png: exportOptions.outputPng,
      jpegQuality: settings.jpegQuality,
    );
  }

  static Uint8List encode(
    img.Image image, {
    bool png = false,
    int jpegQuality = 94,
  }) {
    if (png) return Uint8List.fromList(img.encodePng(image));
    return Uint8List.fromList(
      img.encodeJpg(image, quality: jpegQuality.clamp(1, 100).toInt()),
    );
  }

  static img.Image downscale(img.Image source, int maxDimension) {
    final maxSide = math.max(source.width, source.height);
    if (maxSide <= maxDimension) return source;
    final scale = maxDimension / maxSide;
    return img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()),
      height: math.max(1, (source.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }
}
