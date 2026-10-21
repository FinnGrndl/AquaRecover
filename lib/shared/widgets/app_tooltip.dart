import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

/// How an [AppTooltip] is shown.
enum AppTooltipTrigger {
  /// Touch and hold on phones and tablets, hover with a mouse or trackpad.
  longPressOrHover,

  /// Hover with a pointer only. For controls whose touch-and-hold already
  /// does something, such as reordering or hold-to-compare.
  hoverOnly,
}

/// The app's one help tag: a small dark-glass label that names an icon
/// control when it is touched and held, or hovered on a Mac, a Windows PC
/// or an iPad with a pointer.
///
/// Built on [RawTooltip], so it needs no Material theme. Like the rest of
/// the floating chrome it has no drop shadow: depth comes from the blur,
/// the fill and a hairline edge.
///
/// Most icon buttons already carry a [Semantics] label with the same text.
/// For those, keep [excludeFromSemantics] true (the default) so VoiceOver
/// does not read the name twice. Set it to false only for a control that
/// has no label of its own; the tooltip then names it for assistive
/// technologies too.
class AppTooltip extends StatelessWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.trigger = AppTooltipTrigger.longPressOrHover,
    this.excludeFromSemantics = true,
    this.preferBelow = true,
  });

  final String message;
  final Widget child;
  final AppTooltipTrigger trigger;
  final bool excludeFromSemantics;

  /// Shows the tag below the control when there is room, else above it.
  final bool preferBelow;

  /// How long a pointer rests on a control before its tag appears, close
  /// to the macOS help-tag delay.
  static const hoverDelay = Duration(milliseconds: 600);

  /// How long the tag stays after a finger lifts.
  static const touchDelay = Duration(milliseconds: 1500);

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return child;
    return RawTooltip(
      semanticsTooltip: excludeFromSemantics ? null : message,
      triggerMode: trigger == AppTooltipTrigger.hoverOnly
          ? TooltipTriggerMode.manual
          : TooltipTriggerMode.longPress,
      hoverDelay: hoverDelay,
      touchDelay: touchDelay,
      ignorePointer: true,
      positionDelegate: (c) => positionDependentBox(
        size: c.overlaySize,
        childSize: c.tooltipSize,
        target: c.target,
        verticalOffset: c.targetSize.height / 2 + 6,
        preferBelow: preferBelow,
        margin: 8,
      ),
      tooltipBuilder: (context, animation) => FadeTransition(
        opacity: animation,
        child: AppTooltipLabel(message: message),
      ),
      child: child,
    );
  }
}

/// The tag [AppTooltip] draws; public so tests and previews can show it.
class AppTooltipLabel extends StatelessWidget {
  const AppTooltipLabel({super.key, required this.message});

  final String message;

  static const _radius = BorderRadius.all(Radius.circular(9));

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: ClipRRect(
        borderRadius: _radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(
                0xff1c1f26,
              ).withValues(alpha: highContrast ? .97 : .86),
              borderRadius: _radius,
              border: Border.all(
                color: CupertinoColors.white.withValues(
                  alpha: highContrast ? .34 : .14,
                ),
                width: .5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.6,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: base.copyWith(
                    color: CupertinoColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -.08,
                    height: 1.25,
                    decoration: TextDecoration.none,
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
