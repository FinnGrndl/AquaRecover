import 'package:flutter/cupertino.dart';

import '../../../shared/reduce_motion.dart';
import '../../../l10n/l10n.dart';
import '../editor_tools.dart';
import '../../../shared/widgets/app_tooltip.dart';
import 'editor_glass_surface.dart';
import '../../../shared/widgets/scrollbar_list_view.dart';

class EditorCollapsedPanelButton extends StatelessWidget {
  const EditorCollapsedPanelButton({
    super.key,
    required this.group,
    required this.onPressed,
  });

  final EditorToolGroup group;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.openToolsNamed(group.labelIn(l10n)),
      child: CupertinoButton(
        key: const Key('editor_tool_panel_open'),
        padding: EdgeInsets.zero,
        // The pill stays compact; the hit region keeps the 44 pt minimum.
        minimumSize: const Size(
          kMinInteractiveDimensionCupertino,
          kMinInteractiveDimensionCupertino,
        ),
        onPressed: onPressed,
        child: EditorGlassSurface(
          style: EditorGlassStyle.clear,
          borderRadius: 99,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.openTool(group.labelIn(l10n)),
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: CupertinoColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                CupertinoIcons.chevron_up,
                color: CupertinoColors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditorBottomPanel extends StatelessWidget {
  const EditorBottomPanel({
    super.key,
    required this.group,
    required this.open,
    required this.height,
    required this.onClose,
    required this.child,
    this.animate = true,
  });

  final EditorToolGroup group;
  final bool open;
  final double height;
  final VoidCallback onClose;
  final Widget child;

  /// False follows [height] at once, as while a divider is dragged.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return GlassBottomPanel(
      label: context.l10n.toolsNamed(group.labelIn(context.l10n)),
      open: open,
      height: height,
      onClose: onClose,
      animate: animate,
      contentPadding: group == EditorToolGroup.crop
          ? const EdgeInsets.fromLTRB(14, 44, 14, 10)
          : const EdgeInsets.fromLTRB(14, 48, 14, 18),
      child: child,
    );
  }
}

/// The floating glass tool panel above a [GlassToolRail], with a chevron
/// that collapses it.
class GlassBottomPanel extends StatelessWidget {
  const GlassBottomPanel({
    super.key,
    required this.label,
    required this.open,
    required this.height,
    required this.onClose,
    required this.child,
    this.contentPadding = const EdgeInsets.fromLTRB(14, 48, 14, 18),
    this.scrollable = true,
    this.animate = true,
  });

  final String label;
  final bool open;
  final double height;
  final VoidCallback onClose;
  final Widget child;
  final EdgeInsets contentPadding;

  /// When false, [child] gets the panel's height and handles overflow itself.
  final bool scrollable;

  /// False follows [height] at once, as while a divider is dragged.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!open) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: animate
          ? motionDuration(context, const Duration(milliseconds: 180))
          : Duration.zero,
      curve: Curves.easeOut,
      height: height,
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 7),
      child: EditorGlassSurface(
        borderRadius: 24,
        child: Semantics(
          container: true,
          label: label,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (scrollable)
                ScrollbarListView(padding: contentPadding, children: [child])
              else
                Padding(padding: contentPadding, child: child),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: AppTooltip(
                    message: context.l10n.collapseItem(label),
                    child: Semantics(
                      button: true,
                      label: context.l10n.collapseItem(label),
                      excludeSemantics: true,
                      child: CupertinoButton(
                        key: const Key('editor_tool_panel_close'),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        minimumSize: const Size(
                          kMinInteractiveDimensionCupertino,
                          kMinInteractiveDimensionCupertino,
                        ),
                        onPressed: onClose,
                        child: Icon(
                          CupertinoIcons.chevron_down,
                          size: 17,
                          color: CupertinoColors.white.withValues(alpha: .72),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
