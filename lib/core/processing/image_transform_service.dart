import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/image_transform_settings.dart';

class ImageTransformService {
  const ImageTransformService();

  img.Image apply(img.Image source, ImageTransformSettings settings) {
    if (settings.isIdentity) return source;
    final sourceAspectRatio = source.width / source.height;
    var output = img.Image.from(source);
    final turns = settings.normalizedQuarterTurns;
    if (turns != 0) {
      output = img.copyRotate(output, angle: turns * 90);
    }
    if (settings.flipHorizontal) {
      output = img.flipHorizontal(output);
    }
    if (settings.flipVertical) {
      output = img.flipVertical(output);
    }

    final straighten = settings.straightenDegrees.clamp(-45.0, 45.0);
    if (straighten.abs() >= .0000001) {
      final widthBeforeStraighten = output.width.toDouble();
      final heightBeforeStraighten = output.height.toDouble();
      output = img.copyRotate(
        output,
        angle: straighten,
        interpolation: img.Interpolation.cubic,
      );

      final safeCanvas = _largestSafeCrop(
        outputWidth: output.width.toDouble(),
        outputHeight: output.height.toDouble(),
        sourceWidth: widthBeforeStraighten,
        sourceHeight: heightBeforeStraighten,
        targetAspect: settings.orientedSourceAspectRatio(sourceAspectRatio),
        angleDegrees: straighten,
      );
      output = _cropPixels(output, safeCanvas);
    }

    // The normalized crop is deliberately applied after straightening. The
    // editor overlays it on the same safe canvas, so a handle always selects
    // the pixels that the full-resolution export will produce.
    final normalizedCrop = settings.normalizedCropRect(sourceAspectRatio);
    return _cropNormalized(output, normalizedCrop);
  }

  img.Image _cropNormalized(img.Image source, NormalizedCropRect crop) {
    return _cropPixels(
      source,
      _PixelCropRect(
        left: crop.left * source.width,
        top: crop.top * source.height,
        width: crop.width * source.width,
        height: crop.height * source.height,
      ),
    );
  }

  img.Image _cropPixels(img.Image source, _PixelCropRect crop) {
    final x = crop.left.floor().clamp(0, source.width - 1).toInt();
    final y = crop.top.floor().clamp(0, source.height - 1).toInt();
    final width = crop.width.round().clamp(1, source.width - x).toInt();
    final height = crop.height.round().clamp(1, source.height - y).toInt();
    if (x == 0 && y == 0 && width == source.width && height == source.height) {
      return source;
    }
    return img.copyCrop(source, x: x, y: y, width: width, height: height);
  }

  _PixelCropRect _largestSafeCrop({
    required double outputWidth,
    required double outputHeight,
    required double sourceWidth,
    required double sourceHeight,
    required double targetAspect,
    required double angleDegrees,
  }) {
    final safeTarget = targetAspect.isFinite && targetAspect > 0
        ? targetAspect
        : sourceWidth / sourceHeight;
    final radians = angleDegrees.abs() * math.pi / 180;
    final cosine = math.cos(radians).abs();
    final sine = math.sin(radians).abs();
    final rotationSafety = angleDegrees.abs() > .0000001 ? .98 : 1.0;
    final height =
        math.min(
          sourceWidth / (safeTarget * cosine + sine),
          sourceHeight / (safeTarget * sine + cosine),
        ) *
        rotationSafety;
    final safeHeight = height.clamp(1.0, outputHeight).toDouble();
    final safeWidth = (safeHeight * safeTarget)
        .clamp(1.0, outputWidth)
        .toDouble();
    return _PixelCropRect(
      left: (outputWidth - safeWidth) / 2,
      top: (outputHeight - safeHeight) / 2,
      width: safeWidth,
      height: safeHeight,
    );
  }
}

class _PixelCropRect {
  const _PixelCropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}
