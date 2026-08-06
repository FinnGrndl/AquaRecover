import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../editor_tools.dart';

class EditorToolRail extends StatelessWidget {
  const EditorToolRail({
    super.key,
    required this.groups,
    required this.selectedGroup,
    required this.panelOpen,
    required this.onSelected,
  });

  final List<EditorToolGroup> groups;
  final EditorToolGroup selectedGroup;
  final bool panelOpen;
  final ValueChanged<EditorToolGroup> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xff202328).withValues(alpha: .58),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: CupertinoColors.white.withValues(alpha: .13),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  for (var index = 0; index < groups.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _ToolButton(
                        key: Key('editor_tool_${groups[index].name}'),
                        group: groups[index],
                        selected: groups[index] == selectedGroup && panelOpen,
                        onPressed: () => onSelected(groups[index]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.group,
    required this.selected,
    required this.onPressed,
  });

  final EditorToolGroup group;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final foreground = selected
        ? primary
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final background = selected
        ? primary.withValues(alpha: .14)
        : CupertinoColors.transparent;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      borderRadius: BorderRadius.circular(16),
      color: background,
      onPressed: onPressed,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconFor(group), size: 20, color: foreground),
            const SizedBox(height: 3),
            Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(EditorToolGroup group) => switch (group) {
    EditorToolGroup.presets => CupertinoIcons.wand_stars,
    EditorToolGroup.light => CupertinoIcons.sun_max,
    EditorToolGroup.crop => CupertinoIcons.crop,
    EditorToolGroup.color => CupertinoIcons.color_filter,
    EditorToolGroup.details => CupertinoIcons.slider_horizontal_3,
    EditorToolGroup.effects => CupertinoIcons.cube,
    EditorToolGroup.video => CupertinoIcons.film,
  };
}
