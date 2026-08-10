import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// A horizontally scrolling, discrete value wheel inspired by Apple Photos.
///
/// The fixed center marker represents the selected value. Each crossed tick
/// reports a new value and produces selection haptics on supported phones.
class PrecisionWheel extends StatefulWidget {
  const PrecisionWheel({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.valueFormatter,
    this.divisions,
    this.semanticLabel,
    this.hapticFeedback,
    this.showValue = true,
  }) : assert(max > min),
       assert(divisions == null || divisions > 0);

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final String Function(double value) valueFormatter;
  final String? semanticLabel;
  final bool showValue;

  /// Overrides the platform haptic callback in widget tests.
  final VoidCallback? hapticFeedback;

  @override
  State<PrecisionWheel> createState() => _PrecisionWheelState();
}

class _PrecisionWheelState extends State<PrecisionWheel> {
  static const double _tickSpacing = 9;
  double get _wheelHeight => widget.showValue ? 58 : 48;
  static const Duration _snapDuration = Duration(milliseconds: 150);

  late final ScrollController _scrollController;
  late final FocusNode _focusNode;
  late int _displayedIndex;
  late int _lastReportedIndex;
  bool _userInteractionActive = false;
  bool _syncingExternalValue = false;
  DateTime? _lastHapticAt;

  int get _divisionCount => widget.divisions ?? 100;
  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _displayedIndex = _indexForValue(widget.value);
    _lastReportedIndex = _displayedIndex;
    _scrollController = ScrollController(
      initialScrollOffset: _positionForValue(widget.value) * _tickSpacing,
    )..addListener(_handleScrollOffset);
    _focusNode = FocusNode(debugLabel: 'Precision wheel');
  }

  @override
  void didUpdateWidget(PrecisionWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rangeChanged =
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.divisions != widget.divisions;
    final nextIndex = _indexForValue(widget.value);
    if (rangeChanged ||
        (!_userInteractionActive && nextIndex != _displayedIndex)) {
      _displayedIndex = nextIndex;
      _lastReportedIndex = nextIndex;
      _syncToExternalValue(widget.value);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScrollOffset)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int _indexForValue(double value) {
    return _positionForValue(value).round();
  }

  double _positionForValue(double value) =>
      ((value.clamp(widget.min, widget.max) - widget.min) /
              (widget.max - widget.min) *
              _divisionCount)
          .clamp(0.0, _divisionCount.toDouble());

  double _valueForIndex(int index) {
    final clamped = index.clamp(0, _divisionCount);
    return widget.min + (widget.max - widget.min) * clamped / _divisionCount;
  }

  int _indexForOffset(double offset) =>
      (offset / _tickSpacing).round().clamp(0, _divisionCount);

  void _handleScrollOffset() {
    if (!_scrollController.hasClients || _syncingExternalValue) return;
    final index = _indexForOffset(_scrollController.offset);
    if (index == _displayedIndex) return;
    setState(() => _displayedIndex = index);
    if (index == _lastReportedIndex || !_enabled) return;
    _lastReportedIndex = index;
    widget.onChanged!(_valueForIndex(index));
    _playSelectionHaptic();
  }

  void _playSelectionHaptic() {
    final now = DateTime.now();
    if (_lastHapticAt != null &&
        now.difference(_lastHapticAt!) < const Duration(milliseconds: 24)) {
      return;
    }
    _lastHapticAt = now;
    if (widget.hapticFeedback case final feedback?) {
      feedback();
    } else {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification && !_syncingExternalValue) {
      _focusNode.requestFocus();
      _userInteractionActive = true;
    } else if (notification is ScrollEndNotification &&
        !_syncingExternalValue) {
      final index = _indexForOffset(_scrollController.offset);
      _userInteractionActive = false;
      _snapToIndex(index);
    }
    return false;
  }

  void _selectIndex(int index) {
    if (!_enabled) return;
    _focusNode.requestFocus();
    _userInteractionActive = true;
    unawaited(
      _scrollController
          .animateTo(
            index * _tickSpacing,
            duration: _snapDuration,
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _userInteractionActive = false),
    );
  }

  void _adjustBy(int amount) {
    if (!_enabled) return;
    final next = (_displayedIndex + amount).clamp(0, _divisionCount);
    if (next == _displayedIndex) return;
    _selectIndex(next);
  }

  void _snapToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final target = index * _tickSpacing;
    if ((_scrollController.offset - target).abs() < .1) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _scrollController.jumpTo(target);
      return;
    }
    unawaited(
      _scrollController.animateTo(
        target,
        duration: _snapDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _syncToExternalValue(double value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _positionForValue(value) * _tickSpacing;
      _syncingExternalValue = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(target);
        _syncingExternalValue = false;
        return;
      }
      unawaited(
        _scrollController
            .animateTo(
              target,
              duration: _snapDuration,
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _syncingExternalValue = false),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final separator = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    final displayedValue = widget.value
        .clamp(widget.min, widget.max)
        .toDouble();
    final displayedText = widget.valueFormatter(displayedValue);
    final canDecrease = _enabled && _displayedIndex > 0;
    final canIncrease = _enabled && _displayedIndex < _divisionCount;

    return Semantics(
      label: widget.semanticLabel,
      value: displayedText,
      enabled: _enabled,
      focusable: true,
      increasedValue: canIncrease
          ? widget.valueFormatter(_valueForIndex(_displayedIndex + 1))
          : null,
      decreasedValue: canDecrease
          ? widget.valueFormatter(_valueForIndex(_displayedIndex - 1))
          : null,
      onIncrease: canIncrease ? () => _adjustBy(1) : null,
      onDecrease: canDecrease ? () => _adjustBy(-1) : null,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _adjustBy(-1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _adjustBy(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _adjustBy(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _adjustBy(1),
        },
        child: Focus(
          focusNode: _focusNode,
          child: Listener(
            onPointerDown: _enabled
                ? (_) {
                    _focusNode.requestFocus();
                    _userInteractionActive = true;
                  }
                : null,
            child: SizedBox(
              key: const Key('precision_wheel'),
              height: _wheelHeight,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: CupertinoColors.white.withValues(
                    alpha: _enabled ? .055 : .025,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: separator.withValues(alpha: _enabled ? .55 : .24),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: _handleScrollNotification,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final horizontalPadding =
                                (constraints.maxWidth - _tickSpacing) / 2;
                            return ExcludeSemantics(
                              child: ListView.builder(
                                controller: _scrollController,
                                scrollDirection: Axis.horizontal,
                                physics: _enabled
                                    ? const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
                                      )
                                    : const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.symmetric(
                                  horizontal: horizontalPadding,
                                ),
                                itemExtent: _tickSpacing,
                                itemCount: _divisionCount + 1,
                                itemBuilder: (context, index) =>
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _enabled
                                          ? () => _selectIndex(index)
                                          : null,
                                      child: const SizedBox.expand(),
                                    ),
                              ),
                            );
                          },
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _PrecisionWheelPainter(
                            controller: _scrollController,
                            initialIndex: _displayedIndex,
                            tickSpacing: _tickSpacing,
                            divisionCount: _divisionCount,
                            tickColor: secondary,
                            enabled: _enabled,
                            showValue: widget.showValue,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Align(
                          alignment: widget.showValue
                              ? Alignment.bottomCenter
                              : Alignment.center,
                          child: Container(
                            width: 2,
                            height: widget.showValue ? 27 : 30,
                            margin: EdgeInsets.only(
                              bottom: widget.showValue ? 5 : 0,
                            ),
                            decoration: BoxDecoration(
                              color: _enabled ? primary : secondary,
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: _enabled
                                  ? [
                                      BoxShadow(
                                        color: primary.withValues(alpha: .32),
                                        blurRadius: 7,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      if (widget.showValue)
                        IgnorePointer(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 48),
                              height: 27,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    CupertinoColors.white.withValues(
                                      alpha: .18,
                                    ),
                                    CupertinoColors.white.withValues(
                                      alpha: .07,
                                    ),
                                  ],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(11),
                                ),
                                border: Border(
                                  left: BorderSide(
                                    color: CupertinoColors.white.withValues(
                                      alpha: .12,
                                    ),
                                  ),
                                  right: BorderSide(
                                    color: CupertinoColors.white.withValues(
                                      alpha: .12,
                                    ),
                                  ),
                                  bottom: BorderSide(
                                    color: CupertinoColors.white.withValues(
                                      alpha: .12,
                                    ),
                                  ),
                                ),
                              ),
                              child: Text(
                                displayedText,
                                maxLines: 1,
                                style: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .copyWith(
                                      color: _enabled ? label : secondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
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
      ),
    );
  }
}

class _PrecisionWheelPainter extends CustomPainter {
  _PrecisionWheelPainter({
    required this.controller,
    required this.initialIndex,
    required this.tickSpacing,
    required this.divisionCount,
    required this.tickColor,
    required this.enabled,
    required this.showValue,
  }) : super(repaint: controller);

  final ScrollController controller;
  final int initialIndex;
  final double tickSpacing;
  final int divisionCount;
  final Color tickColor;
  final bool enabled;
  final bool showValue;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = controller.hasClients
        ? controller.offset
        : initialIndex * tickSpacing;
    final centerX = size.width / 2;
    final centerIndex = offset / tickSpacing;
    final visibleRadius = (size.width / tickSpacing / 2).ceil() + 2;
    final first = (centerIndex.floor() - visibleRadius).clamp(0, divisionCount);
    final last = (centerIndex.ceil() + visibleRadius).clamp(0, divisionCount);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1;

    for (var index = first; index <= last; index++) {
      final x = centerX + index * tickSpacing - offset;
      final distance = ((x - centerX).abs() / centerX).clamp(0.0, 1.0);
      final visibility = (1 - distance) * (enabled ? 1 : .48);
      if (visibility <= .02) continue;
      final major = index % 5 == 0;
      final tickHeight = (major ? 16.0 : 10.0) * (1 - distance * .24);
      final curve = distance * distance * (showValue ? 7 : 4);
      final baseline = showValue ? size.height - 6 : size.height / 2 + 8;
      final top = baseline - tickHeight + curve;
      final bottom = baseline + curve;
      paint.color = tickColor.withValues(
        alpha: (major ? .78 : .48) * visibility,
      );
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(_PrecisionWheelPainter oldDelegate) =>
      oldDelegate.initialIndex != initialIndex ||
      oldDelegate.tickSpacing != tickSpacing ||
      oldDelegate.divisionCount != divisionCount ||
      oldDelegate.tickColor != tickColor ||
      oldDelegate.enabled != enabled ||
      oldDelegate.showValue != showValue;
}
