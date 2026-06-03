import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../../../core/models/restoration_settings.dart';

class GpuPreviewFilter extends StatelessWidget {
  const GpuPreviewFilter({
    super.key,
    required this.path,
    required this.settings,
  });
  final String path;
  final RestorationSettings settings;
  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_matrix(settings)),
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Center(child: Text('Preview unavailable for this format.')),
      ),
    );
  }

  static List<double> matrixFor(RestorationSettings s) {
    final red = (1.0 + s.recovery * s.redRecovery * 0.10)
        .clamp(0.6, 1.45)
        .toDouble();
    final green = (1.0 - s.hazeReduction * 0.05).clamp(0.75, 1.2).toDouble();
    final blue = (1.0 - s.recovery * 0.025).clamp(0.75, 1.25).toDouble();
    final contrast = s.contrast.clamp(0.7, 1.6).toDouble();
    final exposure = (1.0 + s.exposure.clamp(-1.0, 1.0).toDouble() * 0.32)
        .clamp(0.55, 1.45)
        .toDouble();
    final bias =
        128.0 * (1.0 - contrast) +
        s.brightness.clamp(-1.0, 1.0).toDouble() * 36.0 +
        s.shadows.clamp(-1.0, 1.0).toDouble() * 10.0 +
        s.highlights.clamp(-1.0, 1.0).toDouble() * 8.0 -
        s.blackPoint.clamp(0.0, 1.0).toDouble() * 28.0;
    return <double>[
      red * contrast * exposure,
      0,
      0,
      0,
      bias + 4,
      0,
      green * contrast * exposure,
      0,
      0,
      bias + 2,
      0,
      0,
      blue * contrast * exposure,
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
}
