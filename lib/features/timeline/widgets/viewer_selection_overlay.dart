import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../core/timeline/timeline_project.dart';
import '../timeline_controller.dart';

/// The selection frame and gestures over the movie viewer's canvas: tap an
/// overlay or title to select it, drag to move it, pinch to resize, and turn
/// two fingers to rotate (snapping to upright with a light tap). A double
/// tap on a title edits its text; a tap on empty canvas selects the main
/// clip under the playhead, as in CapCut.
///
/// Positions map plan (output) pixels to view points with
/// `view = plan px × canvasWidth / outputWidth`; overlays are placed from
/// their stored centre, width, and rotation, so the frame stays still while
/// an in or out animation plays.
class ViewerSelectionOverlay extends StatefulWidget {
  const ViewerSelectionOverlay({
    super.key,
    required this.controller,
    required this.canvasSize,
    this.onEditTitle,
  });

  final TimelineController controller;

  /// Size of the movie canvas in view points.
  final Size canvasSize;

  /// Opens the text editor for the title called with its id.
  final ValueChanged<String>? onEditTitle;

  /// Rotations within this many degrees of upright snap to 0°.
  static const rotationSnapDegrees = 3.0;

  /// Centres within this many points of the canvas middle snap to it.
  static const centerSnapPoints = 6.0;

  /// The unrotated rect of [overlay] in view points on a [canvas] when drawn
  /// with [aspect] (width / height).
  static Rect rectOf(
    TimelineOverlay overlay,
    Size canvas, {
    required double aspect,
  }) {
    final w = overlay.widthFraction * canvas.width;
    final h = w / (aspect <= 0 ? 1 : aspect);
    return Rect.fromCenter(
      center: Offset(
        overlay.centerX * canvas.width,
        overlay.centerY * canvas.height,
      ),
      width: w,
      height: h,
    );
  }

  @override
  State<ViewerSelectionOverlay> createState() => _ViewerSelectionOverlayState();
}

class _ViewerSelectionOverlayState extends State<ViewerSelectionOverlay> {
  TimelineController get _controller => widget.controller;

  // Values at the start of the current gesture.
  String? _dragId;
  late double _startX, _startY, _startWidth, _startRotation;
  Offset _startFocal = Offset.zero;
  bool _rotationSnapped = false;
  bool _snapX = false, _snapY = false;

  /// The aspect a title or overlay is drawn with: the plan's rect for titles
  /// (their measured text), the stored media aspect otherwise.
  double _aspectOf(TimelineOverlay overlay) {
    if (overlay.kind == OverlayKind.text) {
      for (final layer in _controller.plan.layers) {
        if (layer.id == overlay.id && layer.keys.isNotEmpty) {
          final key = layer.keys.last;
          if (key.h > 0) return key.w / key.h;
        }
      }
    }
    return overlay.mediaAspect;
  }

  bool _visible(TimelineOverlay overlay) {
    final t = _controller.playhead;
    final start = math.max(0.0, overlay.start);
    final end = math.min(overlay.end, _controller.project.duration);
    if (overlay.kind == OverlayKind.text &&
        (overlay.title?.text.trim().isEmpty ?? true)) {
      return false;
    }
    if (t < start) return false;
    if (t < end) return true;
    // The movie's last instant still shows items that end with it.
    return start < end && end >= _controller.project.duration - 1e-9;
  }

  Rect _rect(TimelineOverlay overlay) => ViewerSelectionOverlay.rectOf(
    overlay,
    widget.canvasSize,
    aspect: _aspectOf(overlay),
  );

  bool _contains(TimelineOverlay overlay, Offset point, {double slop = 0}) {
    final rect = _rect(overlay).inflate(slop);
    // Undo the rotation about the rect's centre.
    final a = -overlay.rotation * math.pi / 180;
    final d = point - rect.center;
    final local = Offset(
      d.dx * math.cos(a) - d.dy * math.sin(a),
      d.dx * math.sin(a) + d.dy * math.cos(a),
    );
    return rect.contains(rect.center + local);
  }

  /// The topmost visible overlay under [point]: higher lanes first, then the
  /// later item on a lane.
  TimelineOverlay? _hit(Offset point) {
    final candidates =
        [
          for (final (i, o) in _controller.project.overlays.indexed)
            if (_visible(o)) (i, o),
        ]..sort((a, b) {
          final lane = b.$2.lane.compareTo(a.$2.lane);
          if (lane != 0) return lane;
          final start = b.$2.start.compareTo(a.$2.start);
          return start != 0 ? start : b.$1.compareTo(a.$1);
        });
    final selected = _controller.selectedOverlay;
    if (selected != null &&
        _visible(selected) &&
        _contains(selected, point, slop: 12)) {
      return selected;
    }
    for (final (_, o) in candidates) {
      if (_contains(o, point)) return o;
    }
    return null;
  }

  void _onTapUp(TapUpDetails details) {
    final hit = _hit(details.localPosition);
    if (hit != null) {
      _controller.selectItem(TimelineSelection.overlay(hit.id));
    } else {
      _controller.selectClipAtPlayhead();
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final hit = _hit(details.localPosition);
    if (hit == null || hit.kind != OverlayKind.text) return;
    _controller.selectItem(TimelineSelection.overlay(hit.id));
    widget.onEditTitle?.call(hit.id);
  }

  void _onScaleStart(ScaleStartDetails details) {
    final selected = _controller.selectedOverlay;
    TimelineOverlay? target;
    if (selected != null && _visible(selected) && details.pointerCount > 1) {
      // Two fingers anywhere on the canvas work on the selection.
      target = selected;
    } else {
      target = _hit(details.localFocalPoint);
    }
    if (target == null) return;
    if (target.id != selected?.id) {
      _controller.selectItem(TimelineSelection.overlay(target.id));
    }
    _dragId = target.id;
    _startX = target.centerX;
    _startY = target.centerY;
    _startWidth = target.widthFraction;
    _startRotation = target.rotation;
    _startFocal = details.localFocalPoint;
    _rotationSnapped = target.rotation == 0;
    _controller.beginGesture();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final id = _dragId;
    if (id == null) return;
    final size = widget.canvasSize;
    if (size.width <= 0 || size.height <= 0) return;
    final delta = details.localFocalPoint - _startFocal;
    var x = _startX + delta.dx / size.width;
    var y = _startY + delta.dy / size.height;
    // Snap the centre onto the canvas middle lines.
    final snapX =
        ((x - .5) * size.width).abs() < ViewerSelectionOverlay.centerSnapPoints;
    final snapY =
        ((y - .5) * size.height).abs() <
        ViewerSelectionOverlay.centerSnapPoints;
    if (snapX) x = .5;
    if (snapY) y = .5;
    if ((snapX && !_snapX) || (snapY && !_snapY)) {
      HapticFeedback.selectionClick();
    }
    var rotation = _startRotation;
    var width = _startWidth;
    if (details.pointerCount > 1) {
      width = (_startWidth * details.scale)
          .clamp(
            TimelineOverlay.minWidthFraction,
            TimelineOverlay.maxWidthFraction,
          )
          .toDouble();
      rotation = _startRotation + details.rotation * 180 / math.pi;
      final upright = (rotation / 360).roundToDouble() * 360;
      final snapped =
          (rotation - upright).abs() <
          ViewerSelectionOverlay.rotationSnapDegrees;
      if (snapped) rotation = 0;
      if (snapped && !_rotationSnapped) HapticFeedback.lightImpact();
      _rotationSnapped = snapped;
    }
    setState(() {
      _snapX = snapX;
      _snapY = snapY;
    });
    _controller.updateOverlay(
      id,
      (o) => o.copyWith(
        centerX: x,
        centerY: y,
        widthFraction: width,
        rotation: rotation,
      ),
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_dragId == null) return;
    _dragId = null;
    setState(() => _snapX = _snapY = false);
    _controller.endGesture();
  }

  /// VoiceOver alternatives to the gestures.
  void _nudge({
    double dx = 0,
    double dy = 0,
    double scale = 1,
    double turn = 0,
  }) {
    final overlay = _controller.selectedOverlay;
    if (overlay == null) return;
    _controller.updateOverlay(
      overlay.id,
      (o) => o.copyWith(
        centerX: o.centerX + dx,
        centerY: o.centerY + dy,
        widthFraction: (o.widthFraction * scale)
            .clamp(
              TimelineOverlay.minWidthFraction,
              TimelineOverlay.maxWidthFraction,
            )
            .toDouble(),
        rotation: o.rotation + turn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final selected = _controller.selectedOverlay;
        final show = selected != null && _visible(selected);
        final rect = show ? _rect(selected) : null;
        final name = selected?.title != null
            ? 'Title “${selected!.title!.text.replaceAll('\n', ' ')}”'
            : selected?.isVideo ?? false
            ? 'Video overlay'
            : 'Photo overlay';
        return Semantics(
          label: show ? 'Selected $name on the canvas' : 'Movie canvas',
          hint: show
              ? 'Drag to move, pinch to resize, turn two fingers to rotate'
              : 'Tap to select the clip or overlay you see',
          customSemanticsActions: show
              ? {
                  const CustomSemanticsAction(label: 'Move left'): () =>
                      _nudge(dx: -.05),
                  const CustomSemanticsAction(label: 'Move right'): () =>
                      _nudge(dx: .05),
                  const CustomSemanticsAction(label: 'Move up'): () =>
                      _nudge(dy: -.05),
                  const CustomSemanticsAction(label: 'Move down'): () =>
                      _nudge(dy: .05),
                  const CustomSemanticsAction(label: 'Make larger'): () =>
                      _nudge(scale: 1.1),
                  const CustomSemanticsAction(label: 'Make smaller'): () =>
                      _nudge(scale: 1 / 1.1),
                  const CustomSemanticsAction(label: 'Rotate clockwise'): () =>
                      _nudge(turn: 15),
                }
              : null,
          child: GestureDetector(
            key: const Key('timeline_viewer_canvas'),
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onDoubleTapDown: _onDoubleTapDown,
            onDoubleTap: () {},
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: CustomPaint(
              size: widget.canvasSize,
              painter: _SelectionPainter(
                rect: rect,
                rotation: selected?.rotation ?? 0,
                guideX: _snapX && show,
                guideY: _snapY && show,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A thin white frame with a 1 pt dark outline and four corner handles, and
/// centre guides while the item snaps to the middle. No shadows, no motion.
class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.rect,
    required this.rotation,
    required this.guideX,
    required this.guideY,
  });

  final Rect? rect;
  final double rotation;
  final bool guideX, guideY;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()
      ..color = const Color(0x99000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final white = Paint()
      ..color = const Color(0xffffffff)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (guideX) {
      final x = size.width / 2;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), dark)
        ..drawLine(Offset(x, 0), Offset(x, size.height), white);
    }
    if (guideY) {
      final y = size.height / 2;
      canvas
        ..drawLine(Offset(0, y), Offset(size.width, y), dark)
        ..drawLine(Offset(0, y), Offset(size.width, y), white);
    }
    final r = rect;
    if (r == null) return;
    canvas
      ..save()
      ..translate(r.center.dx, r.center.dy)
      ..rotate(rotation * math.pi / 180);
    final local = Rect.fromCenter(
      center: Offset.zero,
      width: r.width,
      height: r.height,
    );
    canvas
      ..drawRect(local, dark)
      ..drawRect(local, white);
    final fill = Paint()..color = const Color(0xffffffff);
    final outline = Paint()
      ..color = const Color(0x99000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final corner in [
      local.topLeft,
      local.topRight,
      local.bottomLeft,
      local.bottomRight,
    ]) {
      canvas
        ..drawCircle(corner, 4.5, fill)
        ..drawCircle(corner, 5, outline);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.rect != rect ||
      old.rotation != rotation ||
      old.guideX != guideX ||
      old.guideY != guideY;
}
