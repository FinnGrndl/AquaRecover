import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../core/models/restoration_settings.dart';

class GpuPreviewFilter extends StatelessWidget {
  const GpuPreviewFilter({
    super.key,
    required this.path,
    required this.settings,
    this.fit = BoxFit.contain,
  });
  final String path;
  final RestorationSettings settings;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_matrix(settings)),
      child: Image.file(
        File(path),
        fit: fit,
        errorBuilder: (_, _, _) =>
            const Center(child: Text('Preview unavailable for this format.')),
      ),
    );
  }

  static List<double> matrixFor(RestorationSettings s) {
    if (s.isIdentity) {
      return const <double>[
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ];
    }
    final correctionScale = (s.recovery / 1.18).clamp(0.0, 1.3).toDouble();
    final red = (1.0 + s.recovery * s.redRecovery * 0.10)
        .clamp(0.6, 1.45)
        .toDouble();
    final green = (1.0 - s.hazeReduction * 0.05 + s.autoWhiteBalance * 0.012)
        .clamp(0.75, 1.2)
        .toDouble();
    final blue = (1.0 - s.recovery * 0.025).clamp(0.75, 1.25).toDouble();
    final contrast = s.contrast.clamp(0.7, 1.6).toDouble();
    final exposure = (1.0 + s.exposure.clamp(-1.0, 1.0).toDouble() * 0.32)
        .clamp(0.55, 1.45)
        .toDouble();
    final saturation = (s.saturation + s.vibrance * 0.36).clamp(0.05, 2.6);
    final colorMatrix = _multiply3(
      _hueMatrix(s.hue.clamp(-1.0, 1.0).toDouble() * math.pi),
      _saturationMatrix(saturation.toDouble()),
    );
    final bias =
        128.0 * (1.0 - contrast) +
        s.brightness.clamp(-1.0, 1.0).toDouble() * 36.0 +
        s.shadows.clamp(-1.0, 1.0).toDouble() * 10.0 +
        s.highlights.clamp(-1.0, 1.0).toDouble() * 8.0 -
        s.blackPoint.clamp(0.0, 1.0).toDouble() * 28.0;
    final scales = [
      red * contrast * exposure,
      green * contrast * exposure,
      blue * contrast * exposure,
    ];
    return <double>[
      colorMatrix[0][0] * scales[0],
      colorMatrix[0][1] * scales[0],
      colorMatrix[0][2] * scales[0],
      0,
      bias + 4 * correctionScale,
      colorMatrix[1][0] * scales[1],
      colorMatrix[1][1] * scales[1],
      colorMatrix[1][2] * scales[1],
      0,
      bias + 2 * correctionScale,
      colorMatrix[2][0] * scales[2],
      colorMatrix[2][1] * scales[2],
      colorMatrix[2][2] * scales[2],
      0,
      bias,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  List<double> _matrix(RestorationSettings s) => matrixFor(s);

  static List<List<double>> _saturationMatrix(double saturation) {
    const r = 0.2126;
    const g = 0.7152;
    const b = 0.0722;
    final inv = 1.0 - saturation;
    return [
      [r * inv + saturation, g * inv, b * inv],
      [r * inv, g * inv + saturation, b * inv],
      [r * inv, g * inv, b * inv + saturation],
    ];
  }

  static List<List<double>> _hueMatrix(double radians) {
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    return [
      [
        .213 + cosA * .787 - sinA * .213,
        .715 - cosA * .715 - sinA * .715,
        .072 - cosA * .072 + sinA * .928,
      ],
      [
        .213 - cosA * .213 + sinA * .143,
        .715 + cosA * .285 + sinA * .140,
        .072 - cosA * .072 - sinA * .283,
      ],
      [
        .213 - cosA * .213 - sinA * .787,
        .715 - cosA * .715 + sinA * .715,
        .072 + cosA * .928 + sinA * .072,
      ],
    ];
  }

  static List<List<double>> _multiply3(
    List<List<double>> a,
    List<List<double>> b,
  ) {
    return [
      for (var row = 0; row < 3; row++)
        [
          for (var col = 0; col < 3; col++)
            a[row][0] * b[0][col] +
                a[row][1] * b[1][col] +
                a[row][2] * b[2][col],
        ],
    ];
  }
}
