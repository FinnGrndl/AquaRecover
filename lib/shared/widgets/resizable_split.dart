import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../reduce_motion.dart';
import 'app_tooltip.dart';

/// The preview sizes the person dragged to, one per editor and orientation
/// (side by side or stacked), kept for the session.
///
/// A split at its default size has no entry, so it keeps following the
/// layout's own default when a panel opens or the window changes.
abstract final class PreviewSplitMemory {
  static final Map<String, double> _ratios = {};

  /// The preview's share of the split, or null for the default.
  static double? ratioOf(String key) => _ratios[key];

  static void remember(String key, double? ratio) {
    if (ratio == null) {
      _ratios.remove(key);
    } else {
      _ratios[key] = ratio;
    }
  }

  @visibleForTesting
  static void clear() => _ratios.clear();
}

/// Lays out a preview and the rest of an editor around a draggable divider.
///
/// The preview always takes the leading side ([Axis.horizontal], the
/// divider is vertical and drags sideways) or the top ([Axis.vertical], the
/// divider is horizontal and drags up and down). [builder] gets the
/// preview's extent along [axis] and lays out both sides itself, so a
/// layout whose preview runs under its controls can still use it; the
/// grabber floats over the boundary.
///
/// The grabber has a 44 pt hit area, a resize cursor and hover highlight
/// with a mouse, arrow keys when focused, an adjustable VoiceOver action,
/// and double-tap to go back to the default size, which drags also snap to.
class ResizableSplit extends StatefulWidget {
  const ResizableSplit({
    super.key,
    required this.axis,
    required this.memoryKey,
    required this.defaultExtent,
    required this.minRest,
    required this.builder,
    this.minPreview = 150,
    this.enabled = true,
    this.handleBias = 0,
    this.gripOffset = 0,
    this.settle,
  });

  final Axis axis;

  /// Which [PreviewSplitMemory] entry this split reads and writes.
  final String memoryKey;

  /// The preview's extent for the split's total extent, when untouched.
  final double Function(double total) defaultExtent;

  /// The least the preview shrinks to, unless the default is smaller.
  final double minPreview;

  /// What the other side keeps at least, unless the default leaves less.
  final double minRest;

  /// Builds both sides for the preview's extent and the rest's, which add
  /// up to the split's. `resizing` is true while a drag or snap runs, for
  /// turning off implicit animations.
  final Widget Function(
    BuildContext context,
    double extent,
    double rest,
    bool resizing,
  )
  builder;

  /// False lays out at the default with no grabber.
  final bool enabled;

  /// Where the 44 pt hit area sits on the boundary: -1 wholly over the
  /// preview, 0 centred, 1 wholly over the rest.
  final double handleBias;

  /// Moves the drawn grip off the boundary, towards the rest when positive.
  final double gripOffset;

  /// Where a released drag or a step comes to rest, for a rest side whose
  /// parts only come in a few sizes: an extent between two of them settles
  /// on the next one the way it was going, so no gap is left over.
  final double Function(double extent, double total, {required bool growing})?
  settle;

  static const handleKey = Key('preview_resize_handle');
  static const hitExtent = 44.0;
  static const _hitLength = 96.0;
  static const _snapDistance = 12.0;
  static const _settleSnapDistance = 28.0;

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snap;
  double _snapFrom = 0;
  double _snapTo = 0;

  /// The extent while dragging or snapping; null follows the memory.
  double? _live;
  double _raw = 0;
  bool _hovered = false;
  bool _focused = false;

  // From the last layout.
  double _total = 0;
  double _default = 0;
  double _min = 0;
  double _max = 0;
  double _extent = 0;

  bool get _horizontal => widget.axis == Axis.horizontal;
  bool get _resizing => _live != null;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(vsync: this)
      ..addListener(_onSnapTick)
      ..addStatusListener(_onSnapStatus);
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  double _clamp(double value) => value.clamp(_min, _max).toDouble();

  double _snapped(double value) =>
      (value - _default).abs() < ResizableSplit._snapDistance
      ? _default
      : value;

  void _remember(double extent) {
    PreviewSplitMemory.remember(
      widget.memoryKey,
      extent == _default || _total <= 0 ? null : extent / _total,
    );
  }

  double _dragFrom = 0;

  double _settled(double extent, {required bool growing}) {
    final settle = widget.settle;
    if (settle == null) return extent;
    return _clamp(settle(extent, _total, growing: growing));
  }

  void _onDragStart(DragStartDetails details) {
    _snap.stop();
    _dragFrom = _extent;
    setState(() {
      _raw = _extent;
      _live = _extent;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _raw += _horizontal ? details.delta.dx : details.delta.dy;
    setState(() => _live = _snapped(_clamp(_raw)));
  }

  void _onDragEnd([DragEndDetails? details]) {
    final live = _live ?? _extent;
    final target = _settled(live, growing: live > _dragFrom);
    if ((target - _default).abs() < ResizableSplit._settleSnapDistance) {
      _animateTo(_default);
    } else if (target != live) {
      _animateTo(target);
    } else {
      _remember(live);
      setState(() => _live = null);
    }
  }

  void _reset() => _animateTo(_default);

  void _animateTo(double target) {
    _remember(target);
    final duration = motionDuration(context, const Duration(milliseconds: 220));
    final from = _live ?? _extent;
    if (duration == Duration.zero || from == target) {
      setState(() => _live = null);
      return;
    }
    _snapFrom = from;
    _snapTo = target;
    _snap.duration = duration;
    _snap.forward(from: 0);
  }

  void _onSnapTick() {
    final t = Curves.easeOutCubic.transform(_snap.value);
    setState(() => _live = _snapFrom + (_snapTo - _snapFrom) * t);
  }

  void _onSnapStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) setState(() => _live = null);
  }

  double get _step => math.max(16, _total * .05);

  /// Grows the preview by [delta], or shrinks it when negative.
  void _adjust(double delta) {
    _snap.stop();
    final next = _snapped(
      _settled(_clamp((_live ?? _extent) + delta), growing: delta > 0),
    );
    _remember(next);
    // Until the next layout, so a second key press builds on this one.
    _extent = next;
    setState(() => _live = null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final grow = _horizontal
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowDown;
    final shrink = _horizontal
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowUp;
    if (key == grow) {
      _adjust(_step);
    } else if (key == shrink) {
      _adjust(-_step);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _reset();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = _horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        _total = total;
        _default = widget.defaultExtent(total).clamp(0.0, total).toDouble();
        _min = math.min(widget.minPreview, _default);
        _max = math.max(total - widget.minRest, _default).toDouble();
        final usable =
            widget.enabled &&
            _max - _min >= ResizableSplit._snapDistance * 2 &&
            total > ResizableSplit.hitExtent;
        final ratio = PreviewSplitMemory.ratioOf(widget.memoryKey);
        _extent = !usable
            ? _default
            : _live ?? (ratio == null ? _default : _clamp(ratio * total));
        final content = widget.builder(
          context,
          _extent,
          total - _extent,
          usable && _resizing,
        );
        if (!usable) return content;
        const hit = ResizableSplit.hitExtent;
        final start = (_extent - hit / 2 + widget.handleBias * hit / 2)
            .clamp(0.0, total - hit)
            .toDouble();
        final cross = _horizontal
            ? constraints.maxHeight
            : constraints.maxWidth;
        final length = math.min(ResizableSplit._hitLength, cross);
        final crossStart = (cross - length) / 2;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: content),
            Positioned(
              left: _horizontal ? start : crossStart,
              top: _horizontal ? crossStart : start,
              width: _horizontal ? hit : length,
              height: _horizontal ? length : hit,
              child: _handle(
                gripCenter: _extent - start + widget.gripOffset,
                length: length,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _handle({required double gripCenter, required double length}) {
    final percent = _total <= 0 ? 0 : (_extent / _total * 100).round();
    final stepPercent = _total <= 0 ? 0 : (_step / _total * 100).round();
    final highlighted = _hovered || _focused || _resizing;
    const thickness = 6.0;
    const gripLength = 40.0;
    final grip = AnimatedContainer(
      duration: motionDuration(context, const Duration(milliseconds: 120)),
      width: _horizontal ? thickness : gripLength,
      height: _horizontal ? gripLength : thickness,
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xff2a2f38).withValues(alpha: .94)
            : const Color(0xff171a20).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: _focused
              ? CupertinoColors.activeBlue
              : CupertinoColors.white.withValues(
                  alpha: highlighted ? .72 : .38,
                ),
          width: _focused ? 1.5 : 1,
        ),
      ),
    );
    final gripPosition = (gripCenter - (thickness + 2) / 2).clamp(
      0.0,
      ResizableSplit.hitExtent - thickness - 2,
    );
    return Semantics(
      container: true,
      label: 'Preview size',
      value: '$percent%',
      increasedValue: '${math.min(100, percent + stepPercent)}%',
      decreasedValue: '${math.max(0, percent - stepPercent)}%',
      hint: 'Drag to resize preview',
      onIncrease: () => _adjust(_step),
      onDecrease: () => _adjust(-_step),
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Reset preview size'): _reset,
      },
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: AppTooltip(
          message: 'Drag to resize preview',
          trigger: AppTooltipTrigger.hoverOnly,
          child: MouseRegion(
            cursor: _horizontal
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              key: ResizableSplit.handleKey,
              behavior: HitTestBehavior.opaque,
              // The adjustable action above stands in for the drag.
              excludeFromSemantics: true,
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragStart: _horizontal ? _onDragStart : null,
              onHorizontalDragUpdate: _horizontal ? _onDragUpdate : null,
              onHorizontalDragEnd: _horizontal ? _onDragEnd : null,
              onHorizontalDragCancel: _horizontal ? _onDragEnd : null,
              onVerticalDragStart: _horizontal ? null : _onDragStart,
              onVerticalDragUpdate: _horizontal ? null : _onDragUpdate,
              onVerticalDragEnd: _horizontal ? null : _onDragEnd,
              onVerticalDragCancel: _horizontal ? null : _onDragEnd,
              onDoubleTap: _reset,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: _horizontal ? gripPosition : 0,
                    top: _horizontal ? 0 : gripPosition,
                    right: _horizontal ? null : 0,
                    bottom: _horizontal ? 0 : null,
                    width: _horizontal ? thickness + 2 : null,
                    height: _horizontal ? null : thickness + 2,
                    child: Center(child: grip),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
