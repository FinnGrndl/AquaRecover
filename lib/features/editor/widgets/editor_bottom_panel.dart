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
                color: CupertinoColors.black.withValues(alpha: .52),
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
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemBackground,
                context,
              ).withValues(alpha: .82),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.separator,
                  context,
                ).withValues(alpha: .62),
              ),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: .18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              group.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .copyWith(
                                    fontSize: 12,
                                    color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.secondaryLabel,
                                      context,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('editor_tool_panel_close'),
                        padding: const EdgeInsets.all(8),
                        minimumSize: Size.zero,
                        onPressed: onClose,
                        child: const Icon(
                          CupertinoIcons.chevron_down,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.separator,
                    context,
                  ).withValues(alpha: .55),
                ),
                Expanded(
                  child: CupertinoScrollbar(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                      children: [child],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
