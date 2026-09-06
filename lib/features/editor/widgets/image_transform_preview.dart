import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../core/models/image_transform_settings.dart';
import '../editor_tools.dart';

typedef TransformPreviewBuilder =
    Widget Function(BoxFit fit, Alignment alignment);

class ImageTransformPreview extends StatefulWidget {
  const ImageTransformPreview({
    super.key,
    required this.settings,
    required this.sourceAspectRatio,
    required this.builder,
    this.showGrid = false,
    this.previewFit = EditorPreviewFit.fit,
    this.onCropChanged,
  });

  final ImageTransformSettings settings;
  final double sourceAspectRatio;
  final TransformPreviewBuilder builder;
  final bool showGrid;
  final EditorPreviewFit previewFit;
  final ValueChanged<ImageTransformSettings>? onCropChanged;

  @override
  State<ImageTransformPreview> createState() => _ImageTransformPreviewState();
}

class _ImageTransformPreviewState extends State<ImageTransformPreview> {
  _CropHandle? _activeHandle;
  Rect? _gestureCropRect;
  Size? _gestureSize;
  ImageTransformSettings? _gestureStartSettings;
  double _gestureStartZoom = 1;
  Offset? _pointerDownPosition;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final sourceAspectRatio = widget.sourceAspectRatio;
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
        var height = maxHeight;
        if (widget.previewFit == EditorPreviewFit.fit) {
          height = width / targetAspect;
          if (height > maxHeight) {
            height = maxHeight;
            width = height * targetAspect;
          }
        }
        final sourceAlignment = _sourceAlignment(settings);
        final requiresCropFill =
            settings.aspectRatio != CropAspectRatio.original ||
            settings.zoom > 1.0000001 ||
            settings.straightenDegrees.abs() > .0000001;
        var content = widget.builder(
          widget.previewFit == EditorPreviewFit.fit && !requiresCropFill
              ? BoxFit.contain
              : BoxFit.cover,
          sourceAlignment,
        );
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
        final zoom = settings.zoom.clamp(1.0, 4.0).toDouble();
        if (zoom > 1.0000001) {
          content = Transform.scale(
            scale: zoom,
            alignment: Alignment(
              settings.offsetX.clamp(-1.0, 1.0).toDouble(),
              settings.offsetY.clamp(-1.0, 1.0).toDouble(),
            ),
            child: content,
          );
        }
        if (settings.straightenDegrees.abs() > .0000001) {
          content = Transform.rotate(
            angle: settings.straightenDegrees * math.pi / 180,
            child: content,
          );
        }
        final straightenCoverage = settings.straightenCoverageScale(
          sourceAspectRatio,
        );
        if (straightenCoverage > 1.0000001) {
          // The safety zoom belongs at the centre. Using the pan alignment
          // here shifts it away from corners and exposes the backdrop.
          content = Transform.scale(
            scale: straightenCoverage,
            alignment: Alignment.center,
            child: content,
          );
        }

        final interactive = widget.showGrid && widget.onCropChanged != null;
        final size = Size(width, height);
        return Center(
          child: SizedBox(
            key: const Key('transform_preview_frame'),
            width: width,
            height: height,
            child: Semantics(
              label: interactive ? 'Crop area' : null,
              hint: interactive
                  ? 'Drag an edge or corner to crop. Drag inside to move the image and pinch to zoom.'
                  : null,
              image: true,
              child: Listener(
                onPointerDown: interactive
                    ? (event) => _pointerDownPosition ??= event.localPosition
                    : null,
                onPointerUp: interactive
                    ? (_) => _pointerDownPosition = null
                    : null,
                onPointerCancel: interactive
                    ? (_) => _pointerDownPosition = null
                    : null,
                child: GestureDetector(
                  key: interactive ? const Key('crop_gesture_surface') : null,
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: interactive
                      ? (details) => _startGesture(details, size)
                      : null,
                  onScaleUpdate: interactive
                      ? (details) => _updateGesture(details, size)
                      : null,
                  onScaleEnd: interactive ? _endGesture : null,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        content,
                        if (widget.showGrid)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _CropGridPainter(
                                cropRect:
                                    _gestureCropRect ?? (Offset.zero & size),
                                showHandles: interactive,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _startGesture(ScaleStartDetails details, Size size) {
    _gestureStartSettings = widget.settings;
    _gestureStartZoom = widget.settings.zoom;
    _gestureSize = size;
    final handle = _CropHandle.hitTest(
      _pointerDownPosition ?? details.localFocalPoint,
      size,
    );
    if (handle == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _activeHandle = handle;
      _gestureCropRect = Offset.zero & size;
    });
  }

  void _updateGesture(ScaleUpdateDetails details, Size size) {
    final startSettings = _gestureStartSettings;
    if (startSettings == null) return;
    final handle = _activeHandle;
    if (handle != null) {
      final gestureSize = _gestureSize ?? size;
      final next = _resizeRect(
        handle: handle,
        focalPoint: details.localFocalPoint,
        size: gestureSize,
        freeform: startSettings.aspectRatio == CropAspectRatio.freeform,
        startingZoom: startSettings.zoom,
      );
      setState(() => _gestureCropRect = next);
      return;
    }

    final zoom = (_gestureStartZoom * details.scale).clamp(1.0, 4.0).toDouble();
    final movementScale = math.max(120.0, math.min(size.width, size.height));
    final current = widget.settings;
    widget.onCropChanged!(
      current.copyWith(
        zoom: zoom,
        offsetX: (current.offsetX - details.focalPointDelta.dx / movementScale)
            .clamp(-1.0, 1.0)
            .toDouble(),
        offsetY: (current.offsetY - details.focalPointDelta.dy / movementScale)
            .clamp(-1.0, 1.0)
            .toDouble(),
      ),
    );
  }

  void _endGesture(ScaleEndDetails details) {
    final startSettings = _gestureStartSettings;
    final cropRect = _gestureCropRect;
    final size = _gestureSize;
    _gestureStartSettings = null;
    _gestureSize = null;
    _activeHandle = null;
    _pointerDownPosition = null;
    if (cropRect == null || size == null || startSettings == null) return;

    final current = startSettings.normalizedCropRect(widget.sourceAspectRatio);
    final nextRect = NormalizedCropRect(
      left: current.left + current.width * cropRect.left / size.width,
      top: current.top + current.height * cropRect.top / size.height,
      width: current.width * cropRect.width / size.width,
      height: current.height * cropRect.height / size.height,
    );
    setState(() => _gestureCropRect = null);
    HapticFeedback.selectionClick();
    widget.onCropChanged!(
      startSettings.withNormalizedCropRect(nextRect, widget.sourceAspectRatio),
    );
  }

  Rect _resizeRect({
    required _CropHandle handle,
    required Offset focalPoint,
    required Size size,
    required bool freeform,
    required double startingZoom,
  }) {
    final bounds = Offset.zero & size;
    final point = Offset(
      focalPoint.dx.clamp(0.0, size.width).toDouble(),
      focalPoint.dy.clamp(0.0, size.height).toDouble(),
    );
    if (freeform) {
      final minWidth = math.min(56.0, size.width);
      final minHeight = math.min(56.0, size.height);
      var left = handle.movesLeft ? point.dx : 0.0;
      var top = handle.movesTop ? point.dy : 0.0;
      var right = handle.movesRight ? point.dx : size.width;
      var bottom = handle.movesBottom ? point.dy : size.height;
      if (right - left < minWidth) {
        if (handle.movesLeft) {
          left = right - minWidth;
        } else {
          right = left + minWidth;
        }
      }
      if (bottom - top < minHeight) {
        if (handle.movesTop) {
          top = bottom - minHeight;
        } else {
          bottom = top + minHeight;
        }
      }
      return Rect.fromLTRB(left, top, right, bottom).intersect(bounds);
    }

    final minScale = math
        .max(math.max(56 / size.width, 56 / size.height), startingZoom / 4)
        .clamp(0.0, 1.0)
        .toDouble();
    late double scale;
    if (handle.isCorner) {
      final horizontal = handle.movesLeft
          ? (size.width - point.dx) / size.width
          : point.dx / size.width;
      final vertical = handle.movesTop
          ? (size.height - point.dy) / size.height
          : point.dy / size.height;
      scale = math.min(horizontal, vertical);
    } else if (handle.movesLeft) {
      scale = (size.width - point.dx) / size.width;
    } else if (handle.movesRight) {
      scale = point.dx / size.width;
    } else if (handle.movesTop) {
      scale = (size.height - point.dy) / size.height;
    } else {
      scale = point.dy / size.height;
    }
    scale = scale.clamp(minScale, 1.0).toDouble();
    final cropWidth = size.width * scale;
    final cropHeight = size.height * scale;
    final left = handle.movesLeft
        ? size.width - cropWidth
        : handle.movesRight
        ? 0.0
        : (size.width - cropWidth) / 2;
    final top = handle.movesTop
        ? size.height - cropHeight
        : handle.movesBottom
        ? 0.0
        : (size.height - cropHeight) / 2;
    return Rect.fromLTWH(left, top, cropWidth, cropHeight);
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

enum _CropHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get movesLeft => this == topLeft || this == bottomLeft || this == left;

  bool get movesTop => this == topLeft || this == topRight || this == top;

  bool get movesRight =>
      this == topRight || this == bottomRight || this == right;

  bool get movesBottom =>
      this == bottomRight || this == bottomLeft || this == bottom;

  bool get isCorner =>
      this == topLeft ||
      this == topRight ||
      this == bottomRight ||
      this == bottomLeft;

  static _CropHandle? hitTest(Offset point, Size size) {
    const hitExtent = 34.0;
    final nearLeft = point.dx <= hitExtent;
    final nearRight = point.dx >= size.width - hitExtent;
    final nearTop = point.dy <= hitExtent;
    final nearBottom = point.dy >= size.height - hitExtent;
    if (nearLeft && nearTop) return topLeft;
    if (nearRight && nearTop) return topRight;
    if (nearRight && nearBottom) return bottomRight;
    if (nearLeft && nearBottom) return bottomLeft;
    if (nearTop) return top;
    if (nearRight) return right;
    if (nearBottom) return bottom;
    if (nearLeft) return left;
    return null;
  }
}

class _CropGridPainter extends CustomPainter {
  const _CropGridPainter({required this.cropRect, required this.showHandles});

  final Rect cropRect;
  final bool showHandles;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = cropRect.intersect(Offset.zero & size);
    final shade = Paint()..color = CupertinoColors.black.withValues(alpha: .48);
    if (rect.top > 0) {
      canvas.drawRect(Rect.fromLTRB(0, 0, size.width, rect.top), shade);
    }
    if (rect.bottom < size.height) {
      canvas.drawRect(
        Rect.fromLTRB(0, rect.bottom, size.width, size.height),
        shade,
      );
    }
    if (rect.left > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, rect.top, rect.left, rect.bottom),
        shade,
      );
    }
    if (rect.right < size.width) {
      canvas.drawRect(
        Rect.fromLTRB(rect.right, rect.top, size.width, rect.bottom),
        shade,
      );
    }

    final shadow = Paint()
      ..color = CupertinoColors.black.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final line = Paint()
      ..color = CupertinoColors.white.withValues(alpha: .78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRect(rect.deflate(1), shadow);
    canvas.drawRect(rect.deflate(1), line);
    line.strokeWidth = .7;
    for (final fraction in const [1 / 3, 2 / 3]) {
      final x = rect.left + rect.width * fraction;
      final y = rect.top + rect.height * fraction;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), line);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
    }
    if (!showHandles) return;

    final handle = Paint()
      ..color = CupertinoColors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    const cornerLength = 18.0;
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + const Offset(cornerLength, 0),
      handle,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + const Offset(0, cornerLength),
      handle,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + const Offset(-cornerLength, 0),
      handle,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + const Offset(0, cornerLength),
      handle,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(-cornerLength, 0),
      handle,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(0, -cornerLength),
      handle,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(cornerLength, 0),
      handle,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(0, -cornerLength),
      handle,
    );
    const edgeLength = 26.0;
    canvas.drawLine(
      Offset(rect.center.dx - edgeLength / 2, rect.top),
      Offset(rect.center.dx + edgeLength / 2, rect.top),
      handle,
    );
    canvas.drawLine(
      Offset(rect.center.dx - edgeLength / 2, rect.bottom),
      Offset(rect.center.dx + edgeLength / 2, rect.bottom),
      handle,
    );
    canvas.drawLine(
      Offset(rect.left, rect.center.dy - edgeLength / 2),
      Offset(rect.left, rect.center.dy + edgeLength / 2),
      handle,
    );
    canvas.drawLine(
      Offset(rect.right, rect.center.dy - edgeLength / 2),
      Offset(rect.right, rect.center.dy + edgeLength / 2),
      handle,
    );
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect ||
      oldDelegate.showHandles != showHandles;
}
