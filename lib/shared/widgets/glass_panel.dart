import 'dart:ui';

import 'package:flutter/cupertino.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 28,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  @override
  Widget build(BuildContext context) {
    final fill = CupertinoDynamicColor.resolve(
      CupertinoColors.systemBackground,
      context,
    ).withValues(alpha: 0.62);
    final border = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    ).withValues(alpha: 0.55);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: border, width: 0.7),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
