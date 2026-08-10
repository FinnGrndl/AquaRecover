import 'package:flutter/cupertino.dart';

import '../editor_tools.dart';
import 'editor_glass_surface.dart';

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
    return Semantics(
      button: true,
      label: 'Open ${group.label} tools',
      child: CupertinoButton(
        key: const Key('editor_tool_panel_open'),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: EditorGlassSurface(
          style: EditorGlassStyle.clear,
          borderRadius: 99,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Open ${group.label}',
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
  });

  final EditorToolGroup group;
  final bool open;
  final double height;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!open) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: height,
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 7),
      child: EditorGlassSurface(
        borderRadius: 24,
        shadow: true,
        child: Semantics(
          container: true,
          label: '${group.label} tools',
          child: Stack(
            fit: StackFit.expand,
            children: [
              CupertinoScrollbar(
                child: ListView(
                  padding: group == EditorToolGroup.crop
                      ? const EdgeInsets.fromLTRB(14, 36, 14, 10)
                      : const EdgeInsets.fromLTRB(14, 48, 14, 18),
                  children: [child],
                ),
              ),
              Positioned(
                top: 2,
                left: 0,
                right: 0,
                child: Center(
                  child: CupertinoButton(
                    key: const Key('editor_tool_panel_close'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    minimumSize: const Size(44, 38),
                    onPressed: onClose,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 17,
                      color: CupertinoColors.white.withValues(alpha: .72),
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
