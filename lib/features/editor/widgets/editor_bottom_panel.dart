import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../editor_tools.dart';

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xff24272b).withValues(alpha: .58),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: CupertinoColors.white.withValues(alpha: .20),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Open ${group.label}',
                      style: CupertinoTheme.of(context).textTheme.textStyle
                          .copyWith(
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xff22252a).withValues(alpha: .62),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: CupertinoColors.white.withValues(alpha: .14),
              ),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: .18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Semantics(
              container: true,
              label: '${group.label} tools',
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CupertinoScrollbar(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 34, 14, 16),
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
                        minimumSize: Size.zero,
                        onPressed: onClose,
                        child: Icon(
                          CupertinoIcons.chevron_down,
                          size: 17,
                          color: CupertinoColors.white.withValues(alpha: .66),
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
    );
  }
}
