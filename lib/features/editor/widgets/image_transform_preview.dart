import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
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
  Rect? _gestureStartRect;
  Offset? _gestureStartFocalPoint;
  Offset? _pointerDownPosition;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final sourceAspectRatio = widget.sourceAspectRatio;
    final orientedAspect = settings.orientedSourceAspectRatio(
      sourceAspectRatio,
    );
    final targetAspect = settings.outputAspectRatio(sourceAspectRatio);
    final interactive = widget.showGrid && widget.onCropChanged != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 640.0;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 640.0;
        final frameAspect = interactive ? orientedAspect : targetAspect;
        var width = maxWidth;
        var height = maxHeight;
        if (interactive || widget.previewFit == EditorPreviewFit.fit) {
          height = width / frameAspect;
          if (height > maxHeight) {
            height = maxHeight;
            width = height * frameAspect;
          }
        }
        final size = Size(width, height);
        final normalizedCrop = settings.normalizedCropRect(sourceAspectRatio);
        final cropRect =
            _gestureCropRect ?? _rectFromNormalized(normalizedCrop, size);
        final content = interactive
            ? _safeSourceCanvas(size, settings)
            : _croppedPreview(
                viewportSize: size,
                orientedAspect: orientedAspect,
                crop: normalizedCrop,
                settings: settings,
                sourceFit:
                    widget.previewFit == EditorPreviewFit.fit &&
                        settings.isIdentity
                    ? BoxFit.contain
                    : BoxFit.cover,
              );
        return Center(
          child: SizedBox(
            key: const Key('transform_preview_frame'),
            width: width,
            height: height,
            child: Semantics(
              label: interactive ? 'Crop area' : null,
              hint: interactive
                  ? 'Drag an edge or corner to crop. Drag inside to move the crop and pinch to resize it.'
                  : null,
              image: true,
              onIncrease: interactive ? () => _adjustCropScale(.9, size) : null,
              onDecrease: interactive
                  ? () => _adjustCropScale(1.1, size)
                  : null,
              customSemanticsActions: interactive
                  ? {
                      const CustomSemanticsAction(
                        label: 'Move crop left',
                      ): () =>
                          _moveCrop(const Offset(-.02, 0), size),
                      const CustomSemanticsAction(
                        label: 'Move crop right',
                      ): () =>
                          _moveCrop(const Offset(.02, 0), size),
                      const CustomSemanticsAction(label: 'Move crop up'): () =>
                          _moveCrop(const Offset(0, -.02), size),
                      const CustomSemanticsAction(
                        label: 'Move crop down',
                      ): () =>
                          _moveCrop(const Offset(0, .02), size),
                    }
                  : null,
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
                                cropRect: cropRect,
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

  Widget _safeSourceCanvas(
    Size size,
    ImageTransformSettings settings, {
    BoxFit sourceFit = BoxFit.cover,
  }) {
    var content = widget.builder(sourceFit, Alignment.center);
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
    if (settings.straightenDegrees.abs() > .0000001) {
      content = Transform.rotate(
        angle: settings.straightenDegrees * math.pi / 180,
        child: content,
      );
    }
    final coverage = settings.straightenCoverageScale(widget.sourceAspectRatio);
    if (coverage > 1.0000001) {
      content = Transform.scale(
        scale: coverage,
        alignment: Alignment.center,
        child: content,
      );
    }
    return SizedBox.fromSize(
      key: const Key('transform_safe_canvas'),
      size: size,
      child: content,
    );
  }

  Widget _croppedPreview({
    required Size viewportSize,
    required double orientedAspect,
    required NormalizedCropRect crop,
    required ImageTransformSettings settings,
    required BoxFit sourceFit,
  }) {
    // Size and place the complete safe canvas so the selected normalized
    // rectangle fills the viewport. Unlike BoxFit alignment, this keeps the
    // pixels outside a previous crop available for later expansion.
    final baseHeight = math.min(
      viewportSize.height,
      viewportSize.width / orientedAspect,
    );
    final canvasSize = Size(orientedAspect * baseHeight, baseHeight);
    final paintScale = math.max(
      viewportSize.width / (crop.width * canvasSize.width),
      viewportSize.height / (crop.height * canvasSize.height),
    );
    final cropCenter = Offset(
      (crop.left + crop.width / 2) * canvasSize.width,
      (crop.top + crop.height / 2) * canvasSize.height,
    );
    final canvasOffset =
        viewportSize.center(Offset.zero) - cropCenter * paintScale;
    return ClipRect(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: canvasSize.width,
            height: canvasSize.height,
            child: Transform(
              key: const Key('transform_selected_crop_canvas'),
              alignment: Alignment.topLeft,
              transform: Matrix4.identity()
                ..translateByDouble(canvasOffset.dx, canvasOffset.dy, 0, 1)
                ..scaleByDouble(paintScale, paintScale, 1, 1),
              child: _safeSourceCanvas(
                canvasSize,
                settings,
                sourceFit: sourceFit,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startGesture(ScaleStartDetails details, Size size) {
    _gestureStartSettings = widget.settings;
    _gestureSize = size;
    final startRect = _rectFromNormalized(
      widget.settings.normalizedCropRect(widget.sourceAspectRatio),
      size,
    );
    _gestureStartRect = startRect;
    _gestureStartFocalPoint = details.localFocalPoint;
    final handle = _CropHandle.hitTest(
      _pointerDownPosition ?? details.localFocalPoint,
      startRect,
    );
    if (handle != null) HapticFeedback.selectionClick();
    setState(() {
      _activeHandle = handle;
      _gestureCropRect = startRect;
    });
  }

  void _updateGesture(ScaleUpdateDetails details, Size size) {
    final startSettings = _gestureStartSettings;
    if (startSettings == null) return;
    final handle = _activeHandle;
    final startRect = _gestureStartRect;
    if (startRect == null) return;
    if (handle != null) {
      final gestureSize = _gestureSize ?? size;
      final next = _resizeRect(
        handle: handle,
        focalPoint: details.localFocalPoint,
        bounds: Offset.zero & gestureSize,
        startRect: startRect,
        freeform: startSettings.aspectRatio == CropAspectRatio.freeform,
      );
      setState(() => _gestureCropRect = next);
      return;
    }

    final startFocal = _gestureStartFocalPoint ?? details.localFocalPoint;
    final translation = details.localFocalPoint - startFocal;
    final desiredScale = details.scale <= 0 ? 1.0 : 1 / details.scale;
    final minScale = _minimumScaleFor(startRect);
    final maxScale = _maximumCenteredScale(startRect, Offset.zero & size);
    final scale = desiredScale.clamp(minScale, maxScale).toDouble();
    final center = startRect.center + translation;
    final resized = Rect.fromCenter(
      center: center,
      width: startRect.width * scale,
      height: startRect.height * scale,
    );
    setState(
      () => _gestureCropRect = _constrainRect(resized, Offset.zero & size),
    );
  }

  void _endGesture(ScaleEndDetails details) {
    final startSettings = _gestureStartSettings;
    final cropRect = _gestureCropRect;
    final size = _gestureSize;
    _gestureStartSettings = null;
    _gestureSize = null;
    _gestureStartRect = null;
    _gestureStartFocalPoint = null;
    _activeHandle = null;
    _pointerDownPosition = null;
    if (cropRect == null || size == null || startSettings == null) return;

    final nextRect = _normalizedFromRect(cropRect, size);
    setState(() => _gestureCropRect = null);
    HapticFeedback.selectionClick();
    widget.onCropChanged!(
      startSettings.withNormalizedCropRect(nextRect, widget.sourceAspectRatio),
    );
  }

  Rect _resizeRect({
    required _CropHandle handle,
    required Offset focalPoint,
    required Rect bounds,
    required Rect startRect,
    required bool freeform,
  }) {
    final point = Offset(
      focalPoint.dx.clamp(bounds.left, bounds.right).toDouble(),
      focalPoint.dy.clamp(bounds.top, bounds.bottom).toDouble(),
    );
    if (freeform) {
      final minWidth = math.min(44.0, bounds.width);
      final minHeight = math.min(44.0, bounds.height);
      var left = handle.movesLeft ? point.dx : startRect.left;
      var top = handle.movesTop ? point.dy : startRect.top;
      var right = handle.movesRight ? point.dx : startRect.right;
      var bottom = handle.movesBottom ? point.dy : startRect.bottom;
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

    final minScale = _minimumScaleFor(startRect);
    final ratio = startRect.width / startRect.height;
    late double scale;
    late double maxScale;
    if (handle.isCorner) {
      final anchor = Offset(
        handle.movesLeft ? startRect.right : startRect.left,
        handle.movesTop ? startRect.bottom : startRect.top,
      );
      final horizontal = (point.dx - anchor.dx).abs() / startRect.width;
      final vertical = (point.dy - anchor.dy).abs() / startRect.height;
      scale = math.min(horizontal, vertical);
      final horizontalRoom = handle.movesLeft
          ? anchor.dx - bounds.left
          : bounds.right - anchor.dx;
      final verticalRoom = handle.movesTop
          ? anchor.dy - bounds.top
          : bounds.bottom - anchor.dy;
      maxScale = math.min(
        horizontalRoom / startRect.width,
        verticalRoom / startRect.height,
      );
      scale = scale.clamp(minScale, maxScale).toDouble();
      final width = startRect.width * scale;
      final height = startRect.height * scale;
      return Rect.fromLTRB(
        handle.movesLeft ? anchor.dx - width : anchor.dx,
        handle.movesTop ? anchor.dy - height : anchor.dy,
        handle.movesRight ? anchor.dx + width : anchor.dx,
        handle.movesBottom ? anchor.dy + height : anchor.dy,
      );
    } else if (handle.movesLeft) {
      scale = (startRect.right - point.dx) / startRect.width;
      maxScale = math.min(
        (startRect.right - bounds.left) / startRect.width,
        _centeredVerticalRoom(startRect, bounds) / startRect.height,
      );
    } else if (handle.movesRight) {
      scale = (point.dx - startRect.left) / startRect.width;
      maxScale = math.min(
        (bounds.right - startRect.left) / startRect.width,
        _centeredVerticalRoom(startRect, bounds) / startRect.height,
      );
    } else if (handle.movesTop) {
      scale = (startRect.bottom - point.dy) / startRect.height;
      maxScale = math.min(
        (startRect.bottom - bounds.top) / startRect.height,
        _centeredHorizontalRoom(startRect, bounds) / startRect.width,
      );
    } else {
      scale = (point.dy - startRect.top) / startRect.height;
      maxScale = math.min(
        (bounds.bottom - startRect.top) / startRect.height,
        _centeredHorizontalRoom(startRect, bounds) / startRect.width,
      );
    }
    scale = scale.clamp(minScale, maxScale).toDouble();
    final cropWidth = startRect.width * scale;
    final cropHeight = cropWidth / ratio;
    final left = handle.movesLeft
        ? startRect.right - cropWidth
        : handle.movesRight
        ? startRect.left
        : startRect.center.dx - cropWidth / 2;
    final top = handle.movesTop
        ? startRect.bottom - cropHeight
        : handle.movesBottom
        ? startRect.top
        : startRect.center.dy - cropHeight / 2;
    return Rect.fromLTWH(left, top, cropWidth, cropHeight);
  }

  double _minimumScaleFor(Rect rect) => math
      .max(math.min(44 / rect.width, 1.0), math.min(44 / rect.height, 1.0))
      .clamp(0.0, 1.0)
      .toDouble();

  double _maximumCenteredScale(Rect rect, Rect bounds) => math.min(
    _centeredHorizontalRoom(rect, bounds) / rect.width,
    _centeredVerticalRoom(rect, bounds) / rect.height,
  );

  double _centeredHorizontalRoom(Rect rect, Rect bounds) =>
      2 * math.min(rect.center.dx - bounds.left, bounds.right - rect.center.dx);

  double _centeredVerticalRoom(Rect rect, Rect bounds) =>
      2 * math.min(rect.center.dy - bounds.top, bounds.bottom - rect.center.dy);

  Rect _constrainRect(Rect rect, Rect bounds) {
    var dx = 0.0;
    var dy = 0.0;
    if (rect.left < bounds.left) dx = bounds.left - rect.left;
    if (rect.right > bounds.right) dx = bounds.right - rect.right;
    if (rect.top < bounds.top) dy = bounds.top - rect.top;
    if (rect.bottom > bounds.bottom) dy = bounds.bottom - rect.bottom;
    return rect.shift(Offset(dx, dy));
  }

  Rect _rectFromNormalized(NormalizedCropRect rect, Size size) => Rect.fromLTWH(
    rect.left * size.width,
    rect.top * size.height,
    rect.width * size.width,
    rect.height * size.height,
  );

  NormalizedCropRect _normalizedFromRect(Rect rect, Size size) =>
      NormalizedCropRect(
        left: rect.left / size.width,
        top: rect.top / size.height,
        width: rect.width / size.width,
        height: rect.height / size.height,
      );

  void _adjustCropScale(double scale, Size size) {
    final current = _rectFromNormalized(
      widget.settings.normalizedCropRect(widget.sourceAspectRatio),
      size,
    );
    final boundedScale = scale.clamp(
      _minimumScaleFor(current),
      _maximumCenteredScale(current, Offset.zero & size),
    );
    final next = _constrainRect(
      Rect.fromCenter(
        center: current.center,
        width: current.width * boundedScale,
        height: current.height * boundedScale,
      ),
      Offset.zero & size,
    );
    _commitRect(next, size);
  }

  void _moveCrop(Offset normalizedDelta, Size size) {
    final current = _rectFromNormalized(
      widget.settings.normalizedCropRect(widget.sourceAspectRatio),
      size,
    );
    final next = _constrainRect(
      current.shift(
        Offset(
          normalizedDelta.dx * size.width,
          normalizedDelta.dy * size.height,
        ),
      ),
      Offset.zero & size,
    );
    _commitRect(next, size);
  }

  void _commitRect(Rect rect, Size size) {
    HapticFeedback.selectionClick();
    widget.onCropChanged?.call(
      widget.settings.withNormalizedCropRect(
        _normalizedFromRect(rect, size),
        widget.sourceAspectRatio,
      ),
    );
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

  static _CropHandle? hitTest(Offset point, Rect cropRect) {
    const hitExtent = 44.0;
    if (!cropRect.inflate(hitExtent).contains(point)) return null;
    final nearLeft = (point.dx - cropRect.left).abs() <= hitExtent;
    final nearRight = (point.dx - cropRect.right).abs() <= hitExtent;
    final nearTop = (point.dy - cropRect.top).abs() <= hitExtent;
    final nearBottom = (point.dy - cropRect.bottom).abs() <= hitExtent;
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
