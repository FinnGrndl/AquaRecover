import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

enum EditorGlassStyle { clear, regular }

/// Shared material for the editor's floating navigation and control layer.
///
/// Content cards remain opaque. This surface is reserved for controls that
/// float above the photo or video, matching Apple's material hierarchy.
/// Depth comes from the blur and fill alone: no drop shadow and no sheen,
/// only a hairline edge that gets stronger with Increase Contrast.
class EditorGlassSurface extends StatelessWidget {
  const EditorGlassSurface({
    super.key,
    required this.child,
    this.style = EditorGlassStyle.regular,
    this.borderRadius = 22,
    this.padding = EdgeInsets.zero,
    this.tint,
  });

  final Widget child;
  final EditorGlassStyle style;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final clear = style == EditorGlassStyle.clear;
    final baseTint =
        tint ?? (clear ? const Color(0xff171a20) : const Color(0xff24272d));
    final baseOpacity = highContrast
        ? (clear ? .90 : .96)
        : (clear ? .48 : .70);
    // A hairline keeps the edge readable over bright footage. Depth comes
    // from the blur and fill alone, so there is no drop shadow or sheen.
    final hairlineOpacity = highContrast ? .30 : .10;
    final radius = BorderRadius.circular(borderRadius);

    return ClipRRect(
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
              color: CupertinoColors.white.withValues(alpha: hairlineOpacity),
              width: .5,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
