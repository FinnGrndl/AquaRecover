import 'package:flutter/cupertino.dart';
import '../../../shared/widgets/app_tooltip.dart';

import '../editor_tools.dart';
import 'editor_glass_surface.dart';

/// One tab of a [GlassToolRail].
class GlassToolRailItem {
  const GlassToolRailItem({
    required this.key,
    required this.icon,
    required this.label,
  });

  final Key key;
  final IconData icon;
  final String label;
}

/// The floating glass tab bar at the bottom of the editors. Tapping the
/// selected tab again toggles its panel, like the Photos editor.
class GlassToolRail extends StatelessWidget {
  const GlassToolRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.panelOpen,
    required this.onSelected,
    this.semanticLabel = 'Editing tools',
  });

  final List<GlassToolRailItem> items;
  final int selectedIndex;
  final bool panelOpen;
  final ValueChanged<int> onSelected;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        height: 60,
        child: EditorGlassSurface(
          style: EditorGlassStyle.clear,
          borderRadius: 30,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _ToolButton(
                    key: items[i].key,
                    item: items[i],
                    selected: i == selectedIndex,
                    panelOpen: panelOpen,
                    onPressed: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    return GlassToolRail(
      items: [
        for (final group in groups)
          GlassToolRailItem(
            key: Key('editor_tool_${group.name}'),
            icon: _iconFor(group),
            label: group.label,
          ),
      ],
      selectedIndex: groups.indexOf(selectedGroup),
      panelOpen: panelOpen,
      onSelected: (index) => onSelected(groups[index]),
    );
  }

  static IconData _iconFor(EditorToolGroup group) => switch (group) {
    EditorToolGroup.presets => CupertinoIcons.rectangle_grid_2x2,
    EditorToolGroup.light => CupertinoIcons.slider_horizontal_3,
    EditorToolGroup.crop => CupertinoIcons.crop_rotate,
    EditorToolGroup.color => CupertinoIcons.color_filter,
    EditorToolGroup.details => CupertinoIcons.scope,
    EditorToolGroup.effects => CupertinoIcons.sparkles,
    EditorToolGroup.video => CupertinoIcons.film,
  };
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.item,
    required this.selected,
    required this.panelOpen,
    required this.onPressed,
  });

  final GlassToolRailItem item;
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
        ? 'Collapse ${item.label} tools'
        : 'Open ${item.label} tools';
    return AppTooltip(
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
                Icon(item.icon, size: 20, color: foreground),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: foreground,
                        fontSize: 11,
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
}
