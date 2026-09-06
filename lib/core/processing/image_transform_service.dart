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

    final targetAspect = settings.outputAspectRatio(sourceAspectRatio);
    final normalizedCrop = settings.normalizedCropRect(sourceAspectRatio);
    final cropX = (normalizedCrop.left * output.width)
        .floor()
        .clamp(0, output.width - 1)
        .toInt();
    final cropY = (normalizedCrop.top * output.height)
        .floor()
        .clamp(0, output.height - 1)
        .toInt();
    final cropWidth = (normalizedCrop.width * output.width)
        .round()
        .clamp(1, output.width - cropX)
        .toInt();
    final cropHeight = (normalizedCrop.height * output.height)
        .round()
        .clamp(1, output.height - cropY)
        .toInt();
    if (cropX != 0 ||
        cropY != 0 ||
        cropWidth != output.width ||
        cropHeight != output.height) {
      output = img.copyCrop(
        output,
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
      );
    }

    final straighten = settings.straightenDegrees.clamp(-45.0, 45.0);
    if (straighten.abs() < .0000001) return output;
    final widthBeforeStraighten = output.width.toDouble();
    final heightBeforeStraighten = output.height.toDouble();
    output = img.copyRotate(
      output,
      angle: straighten,
      interpolation: img.Interpolation.cubic,
    );

    final baseCrop = _largestSafeCrop(
      outputWidth: output.width.toDouble(),
      outputHeight: output.height.toDouble(),
      sourceWidth: widthBeforeStraighten,
      sourceHeight: heightBeforeStraighten,
      targetAspect: targetAspect,
      angleDegrees: straighten,
    );
    final x = baseCrop.left.floor().clamp(0, output.width - 1).toInt();
    final y = baseCrop.top.floor().clamp(0, output.height - 1).toInt();
    final width = baseCrop.width.round().clamp(1, output.width - x).toInt();
    final height = baseCrop.height.round().clamp(1, output.height - y).toInt();
    if (x == 0 && y == 0 && width == output.width && height == output.height) {
      return output;
    }
    return img.copyCrop(output, x: x, y: y, width: width, height: height);
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
