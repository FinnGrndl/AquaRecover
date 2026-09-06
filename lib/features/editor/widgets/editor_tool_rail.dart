import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;

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
    return Semantics(
      container: true,
      label: 'Editing tools',
      child: SizedBox(
        height: 60,
        child: EditorGlassSurface(
          style: EditorGlassStyle.clear,
          borderRadius: 30,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            children: [
              for (final group in groups)
                Expanded(
                  child: _ToolButton(
                    key: Key('editor_tool_${group.name}'),
                    group: group,
                    selected: group == selectedGroup,
                    panelOpen: panelOpen,
                    onPressed: () => onSelected(group),
                  ),
                ),
            ],
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
    required this.panelOpen,
    required this.onPressed,
  });

  final EditorToolGroup group;
  final bool selected;
  final bool panelOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final foreground = selected
        ? primary
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final action = selected && panelOpen
        ? 'Collapse ${group.label} tools'
        : 'Open ${group.label} tools';
    return Tooltip(
      message: action,
      child: Semantics(
        button: true,
        selected: selected,
        label: action,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          pressedOpacity: .55,
          onPressed: onPressed,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_iconFor(group), size: 20, color: foreground),
                const SizedBox(height: 3),
                Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: foreground,
                        fontSize: 10.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(EditorToolGroup group) => switch (group) {
    EditorToolGroup.presets => CupertinoIcons.rectangle_grid_2x2,
    EditorToolGroup.light => CupertinoIcons.slider_horizontal_3,
    EditorToolGroup.crop => CupertinoIcons.crop_rotate,
    EditorToolGroup.color => CupertinoIcons.color_filter,
    EditorToolGroup.details => CupertinoIcons.scope,
    EditorToolGroup.effects => CupertinoIcons.color_filter,
    EditorToolGroup.video => CupertinoIcons.film,
  };
}
