import 'package:flutter/cupertino.dart';

import '../editor_tools.dart';

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
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.separator,
            context,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: .08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
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
                        style: CupertinoTheme.of(context).textTheme.textStyle
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        group.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CupertinoTheme.of(context).textTheme.textStyle
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
                  child: const Icon(CupertinoIcons.chevron_down, size: 20),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.separator,
              context,
            ),
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
    );
  }
}
