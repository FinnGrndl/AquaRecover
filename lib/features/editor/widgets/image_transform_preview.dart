import 'package:flutter/cupertino.dart';

import '../../../core/models/image_transform_settings.dart';

typedef TransformPreviewBuilder =
    Widget Function(BoxFit fit, Alignment alignment);

class ImageTransformPreview extends StatelessWidget {
  const ImageTransformPreview({
    super.key,
    required this.settings,
    required this.sourceAspectRatio,
    required this.builder,
    this.showGrid = false,
  });

  final ImageTransformSettings settings;
  final double sourceAspectRatio;
  final TransformPreviewBuilder builder;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    final targetAspect = settings.outputAspectRatio(sourceAspectRatio);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 640.0;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 640.0;
        var width = maxWidth;
        var height = width / targetAspect;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * targetAspect;
        }
        final sourceAlignment = _sourceAlignment(settings);
        var content = builder(BoxFit.cover, sourceAlignment);
        content = RotatedBox(
          quarterTurns: settings.normalizedQuarterTurns,
          child: content,
        );
        if (settings.flipHorizontal || settings.flipVertical) {
          content = Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(
              settings.flipHorizontal ? -1 : 1,
              settings.flipVertical ? -1 : 1,
              1,
            ),
            child: content,
          );
        }
        content = Transform.scale(
          scale: settings.zoom.clamp(1.0, 4.0).toDouble(),
          alignment: Alignment(
            settings.offsetX.clamp(-1.0, 1.0).toDouble(),
            settings.offsetY.clamp(-1.0, 1.0).toDouble(),
          ),
          child: content,
        );
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  content,
                  if (showGrid)
                    const IgnorePointer(
                      child: CustomPaint(painter: _CropGridPainter()),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Alignment _sourceAlignment(ImageTransformSettings settings) {
    var x = settings.flipHorizontal ? -settings.offsetX : settings.offsetX;
    var y = settings.flipVertical ? -settings.offsetY : settings.offsetY;
    final transformed = switch (settings.normalizedQuarterTurns) {
      1 => (y, -x),
      2 => (-x, -y),
      3 => (-y, x),
      _ => (x, y),
    };
    x = transformed.$1.clamp(-1.0, 1.0).toDouble();
    y = transformed.$2.clamp(-1.0, 1.0).toDouble();
    return Alignment(x, y);
  }
}

class _CropGridPainter extends CustomPainter {
  const _CropGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = CupertinoColors.black.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final line = Paint()
      ..color = CupertinoColors.white.withValues(alpha: .78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final border = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    canvas.drawRect(border, shadow);
    canvas.drawRect(border, line..strokeWidth = 1.4);
    line.strokeWidth = .7;
    for (final fraction in const [1 / 3, 2 / 3]) {
      final x = size.width * fraction;
      final y = size.height * fraction;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) => false;
}
