import 'package:flutter/cupertino.dart';

import 'editor_glass_surface.dart';

/// The floating top bar used over photos, videos, and the movie viewer: a
/// glass back capsule, a centred title with a subtitle, and the screen's
/// primary action on the trailing side.
///
/// The trailing action is a filled capsule button of its own, so it gets no
/// glass behind it: glass never layers under an opaque control. Over photos
/// the screen adds a dark scrim band behind the bar instead of text shadows.
class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({
    super.key,
    required this.leadingLabel,
    required this.onLeadingPressed,
    required this.title,
    required this.subtitle,
    required this.trailingWidth,
    required this.trailing,
    this.onTitlePressed,
    this.leadingKey,
    this.leadingWidth = 108,
    this.showBackChevron = true,
  });

  final String leadingLabel;
  final VoidCallback? onLeadingPressed;
  final String title;
  final String subtitle;
  final double trailingWidth;
  final Widget trailing;

  /// Makes the title tappable, for example to rename.
  final VoidCallback? onTitlePressed;
  final Key? leadingKey;
  final double leadingWidth;

  /// False for a modal's Cancel button, which closes rather than goes back.
  final bool showBackChevron;

  @override
  Widget build(BuildContext context) {
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    Widget titleBlock = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textStyle.copyWith(
            color: CupertinoColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textStyle.copyWith(
            color: CupertinoColors.white.withValues(alpha: .86),
            fontSize: 12,
          ),
        ),
      ],
    );
    if (onTitlePressed != null) {
      titleBlock = Semantics(
        button: true,
        hint: 'Rename',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTitlePressed,
          child: titleBlock,
        ),
      );
    }
    // Like a system navigation bar, the 48 pt bar keeps its height and lets
    // its text grow only a little with larger Dynamic Type sizes, so the title
    // and subtitle never spill out of it.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: _bar(titleBlock),
    );
  }

  /// The largest text scale the bar's labels follow.
  static const maxTextScale = 1.1;

  Widget _bar(Widget titleBlock) {
    return SizedBox(
      height: 48,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: leadingWidth + 8,
            right: trailingWidth + 8,
            top: 3,
            bottom: 3,
            child: titleBlock,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: leadingWidth,
              height: 46,
              child: EditorGlassSurface(
                style: EditorGlassStyle.clear,
                borderRadius: 99,
                child: CupertinoButton(
                  key: leadingKey,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(
                    kMinInteractiveDimensionCupertino,
                    kMinInteractiveDimensionCupertino,
                  ),
                  borderRadius: BorderRadius.circular(99),
                  onPressed: onLeadingPressed,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showBackChevron) ...[
                        Icon(
                          CupertinoIcons.chevron_back,
                          size: 20,
                          color: CupertinoColors.white.withValues(
                            alpha: onLeadingPressed == null ? .38 : 1,
                          ),
                        ),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          leadingLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CupertinoColors.white.withValues(
                              alpha: onLeadingPressed == null ? .38 : 1,
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
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: trailingWidth, height: 46, child: trailing),
          ),
        ],
      ),
    );
  }
}

/// A round glass icon button matching the editor's floating controls.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = kMinInteractiveDimensionCupertino,
    this.iconSize = 19,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: EditorGlassSurface(
          style: EditorGlassStyle.clear,
          borderRadius: 99,
          tint: tint,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.square(size),
            borderRadius: BorderRadius.circular(99),
            onPressed: onPressed,
            child: Icon(
              icon,
              size: iconSize,
              color: CupertinoColors.white.withValues(
                alpha: onPressed == null ? .34 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
