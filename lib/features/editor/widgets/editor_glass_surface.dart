import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

enum EditorGlassStyle { clear, regular }

/// Shared material for the editor's floating navigation and control layer.
///
/// Content cards remain opaque. This surface is reserved for controls that
/// float above the photo or video, matching Apple's material hierarchy.
class EditorGlassSurface extends StatelessWidget {
  const EditorGlassSurface({
    super.key,
    required this.child,
    this.style = EditorGlassStyle.regular,
    this.borderRadius = 22,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.shadow = false,
  });

  final Widget child;
  final EditorGlassStyle style;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final clear = style == EditorGlassStyle.clear;
    final baseTint =
        tint ?? (clear ? const Color(0xff171a20) : const Color(0xff24272d));
    final baseOpacity = highContrast
        ? (clear ? .90 : .96)
        : (clear ? .48 : .70);
    final rimOpacity = highContrast ? .34 : (clear ? .20 : .16);
    final radius = BorderRadius.circular(borderRadius);

    final surface = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(
          sigmaX: highContrast ? 14 : (clear ? 22 : 26),
          sigmaY: highContrast ? 14 : (clear ? 22 : 26),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: baseTint.withValues(alpha: baseOpacity),
            borderRadius: radius,
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: rimOpacity),
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CupertinoColors.white.withValues(
                    alpha: highContrast ? .08 : .11,
                  ),
                  CupertinoColors.transparent,
                  CupertinoColors.black.withValues(alpha: clear ? .08 : .12),
                ],
                stops: const [0, .42, 1],
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
    if (!shadow) return surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: .26),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: surface,
    );
  }
}
