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
      height: 76,
      child: CupertinoScrollbar(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemBuilder: (context, index) {
            final group = groups[index];
            return _ToolButton(
              key: Key('editor_tool_${group.name}'),
              group: group,
              selected: group == selectedGroup && panelOpen,
              onPressed: () => onSelected(group),
            );
          },
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemCount: groups.length,
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
        : CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground,
            context,
          );
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      borderRadius: BorderRadius.circular(16),
      color: background,
      onPressed: onPressed,
      child: SizedBox(
        width: 92,
        height: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconFor(group), size: 20, color: foreground),
            const SizedBox(height: 5),
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
    EditorToolGroup.color => CupertinoIcons.color_filter,
    EditorToolGroup.details => CupertinoIcons.slider_horizontal_3,
    EditorToolGroup.effects => CupertinoIcons.sparkles,
    EditorToolGroup.compare => CupertinoIcons.square_split_1x2,
    EditorToolGroup.video => CupertinoIcons.film,
  };
}
