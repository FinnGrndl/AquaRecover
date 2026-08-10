import 'package:flutter/cupertino.dart';

import '../editor_tools.dart';
import 'editor_glass_surface.dart';

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
      height: 58,
      child: EditorGlassSurface(
        style: EditorGlassStyle.clear,
        borderRadius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            for (var index = 0; index < groups.length; index++) ...[
              if (index > 0) const SizedBox(width: 5),
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
      borderRadius: BorderRadius.circular(15),
      color: background,
      onPressed: onPressed,
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconFor(group), size: 18, color: foreground),
            const SizedBox(height: 2),
            Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                color: foreground,
                fontSize: 11,
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
