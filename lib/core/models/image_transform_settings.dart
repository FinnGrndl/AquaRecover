import 'dart:math' as math;

enum CropAspectRatio { original, freeform, square, fourThree, sixteenNine }

extension CropAspectRatioX on CropAspectRatio {
  String get label => switch (this) {
    CropAspectRatio.original => 'Original',
    CropAspectRatio.freeform => 'Free',
    CropAspectRatio.square => 'Square',
    CropAspectRatio.fourThree => '4:3',
    CropAspectRatio.sixteenNine => '16:9',
  };

  double resolve(
    double orientedSourceAspectRatio, {
    double customAspectRatio = 4 / 3,
  }) {
    final portrait = orientedSourceAspectRatio < 1;
    return switch (this) {
      CropAspectRatio.original => orientedSourceAspectRatio,
      CropAspectRatio.freeform => customAspectRatio.clamp(.25, 4).toDouble(),
      CropAspectRatio.square => 1,
      CropAspectRatio.fourThree => portrait ? 3 / 4 : 4 / 3,
      CropAspectRatio.sixteenNine => portrait ? 9 / 16 : 16 / 9,
    };
  }
}

class NormalizedCropRect {
  const NormalizedCropRect({
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

class ImageTransformSettings {
  const ImageTransformSettings({
    this.aspectRatio = CropAspectRatio.original,
    this.zoom = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.quarterTurns = 0,
    this.straightenDegrees = 0,
    this.customAspectRatio = 4 / 3,
    this.flipHorizontal = false,
    this.flipVertical = false,
  });

  final CropAspectRatio aspectRatio;
  final double zoom;
  final double offsetX;
  final double offsetY;
  final int quarterTurns;
  final double straightenDegrees;
  final double customAspectRatio;
  final bool flipHorizontal;
  final bool flipVertical;

  int get normalizedQuarterTurns => quarterTurns % 4;

  bool get swapsDimensions => normalizedQuarterTurns.isOdd;

  bool get isIdentity =>
      aspectRatio == CropAspectRatio.original &&
      (zoom - 1).abs() < .0000001 &&
      offsetX.abs() < .0000001 &&
      offsetY.abs() < .0000001 &&
      normalizedQuarterTurns == 0 &&
      straightenDegrees.abs() < .0000001 &&
      !flipHorizontal &&
      !flipVertical;

  double orientedSourceAspectRatio(double sourceAspectRatio) {
    final safe = sourceAspectRatio.isFinite && sourceAspectRatio > 0
        ? sourceAspectRatio
        : 4 / 3;
    return swapsDimensions ? 1 / safe : safe;
  }

  double outputAspectRatio(double sourceAspectRatio) {
    return aspectRatio.resolve(
      orientedSourceAspectRatio(sourceAspectRatio),
      customAspectRatio: customAspectRatio,
    );
  }

  /// Extra preview scale needed to keep a straightened image behind the crop.
  ///
  /// The calculation finds the largest rectangle with the requested output
  /// ratio that fits inside the rotated source. Scaling that rectangle to the
  /// crop viewport prevents empty corners while straightening.
  double straightenCoverageScale(double sourceAspectRatio) {
    final degrees = straightenDegrees.clamp(-45.0, 45.0).abs();
    if (degrees < .0000001) return 1;
    final source = orientedSourceAspectRatio(sourceAspectRatio);
    final target = outputAspectRatio(sourceAspectRatio);
    final sourceWidth = source > target ? source : target;
    final sourceHeight = source > target ? 1.0 : target / source;
    final radians = degrees * math.pi / 180;
    final cosine = math.cos(radians).abs();
    final sine = math.sin(radians).abs();
    final safeHeight =
        math.min(
          sourceWidth / (target * cosine + sine),
          sourceHeight / (target * sine + cosine),
        ) *
        .98;
    if (!safeHeight.isFinite || safeHeight <= 0) return 1;
    return math.max(1.0, 1 / safeHeight);
  }

  NormalizedCropRect normalizedCropRect(double sourceAspectRatio) {
    final oriented = orientedSourceAspectRatio(sourceAspectRatio);
    final target = outputAspectRatio(sourceAspectRatio);
    var width = 1.0;
    var height = 1.0;
    if (oriented > target) {
      width = target / oriented;
    } else if (oriented < target) {
      height = oriented / target;
    }
    final safeZoom = zoom.clamp(1.0, 4.0).toDouble();
    width /= safeZoom;
    height /= safeZoom;
    final safeX = offsetX.clamp(-1.0, 1.0).toDouble();
    final safeY = offsetY.clamp(-1.0, 1.0).toDouble();
    return NormalizedCropRect(
      left: (1 - width) * (safeX + 1) / 2,
      top: (1 - height) * (safeY + 1) / 2,
      width: width,
      height: height,
    );
  }

  ImageTransformSettings copyWith({
    CropAspectRatio? aspectRatio,
    double? zoom,
    double? offsetX,
    double? offsetY,
    int? quarterTurns,
    double? straightenDegrees,
    double? customAspectRatio,
    bool? flipHorizontal,
    bool? flipVertical,
  }) {
    return ImageTransformSettings(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      zoom: zoom ?? this.zoom,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      quarterTurns: quarterTurns ?? this.quarterTurns,
      straightenDegrees: straightenDegrees ?? this.straightenDegrees,
      customAspectRatio: customAspectRatio ?? this.customAspectRatio,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
    );
  }

  Map<String, Object> toJson() => {
    'aspectRatio': aspectRatio.name,
    'zoom': zoom,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'quarterTurns': normalizedQuarterTurns,
    'straightenDegrees': straightenDegrees,
    'customAspectRatio': customAspectRatio,
    'flipHorizontal': flipHorizontal,
    'flipVertical': flipVertical,
  };

  static ImageTransformSettings fromJson(Map<String, Object?> map) {
    final aspectName = map['aspectRatio'] as String?;
    final aspect = CropAspectRatio.values.firstWhere(
      (value) => value.name == aspectName,
      orElse: () => CropAspectRatio.original,
    );
    return ImageTransformSettings(
      aspectRatio: aspect,
      zoom: (map['zoom'] as num?)?.toDouble() ?? 1,
      offsetX: (map['offsetX'] as num?)?.toDouble() ?? 0,
      offsetY: (map['offsetY'] as num?)?.toDouble() ?? 0,
      quarterTurns: (map['quarterTurns'] as num?)?.toInt() ?? 0,
      straightenDegrees: (map['straightenDegrees'] as num?)?.toDouble() ?? 0,
      customAspectRatio:
          (map['customAspectRatio'] as num?)?.toDouble() ?? 4 / 3,
      flipHorizontal: map['flipHorizontal'] as bool? ?? false,
      flipVertical: map['flipVertical'] as bool? ?? false,
    );
  }
}
