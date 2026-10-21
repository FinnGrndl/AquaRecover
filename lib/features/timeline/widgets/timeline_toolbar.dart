import 'package:flutter/cupertino.dart';
import '../../../shared/widgets/app_tooltip.dart';

import '../../editor/widgets/editor_glass_surface.dart';
import '../timeline_theme.dart';
import '../../../shared/widgets/mouse_drag_scroll.dart';

/// One item of a [TimelineToolbar].
class TimelineToolItem {
  const TimelineToolItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.key,
    this.active = false,
    this.destructive = false,
    this.hint,
  });

  final String id;
  final Key? key;
  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback? onPressed;

  /// The tool whose panel is open; drawn with a capsule fill.
  final bool active;

  /// Drawn in system red, like Delete.
  final bool destructive;
}

/// The movie editor's bottom toolbar: monochrome symbols with short labels
/// on the editor's floating glass. Its items follow the selection; with
/// something selected, a leading back chevron returns to the root tools. The
/// open tool is marked by a capsule fill, not by colour alone. When the items
/// do not fit, the row scrolls and its edges fade.
class TimelineToolbar extends StatefulWidget {
  const TimelineToolbar({
    super.key,
    required this.items,
    this.onBack,
    this.backLabel = 'All tools',
    this.semanticLabel = 'Movie tools',
  });

  final List<TimelineToolItem> items;

  /// Shows the leading back chevron when set.
  final VoidCallback? onBack;
  final String backLabel;
  final String semanticLabel;

  static const height = 62.0;

  @override
  State<TimelineToolbar> createState() => _TimelineToolbarState();
}

class _TimelineToolbarState extends State<TimelineToolbar> {
  final _scroll = ScrollController();
  bool _fadeStart = false;
  bool _fadeEnd = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onMetrics(ScrollMetrics metrics) {
    final start = metrics.pixels > 1;
    final end = metrics.pixels < metrics.maxScrollExtent - 1;
    if (start != _fadeStart || end != _fadeEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _fadeStart = start;
            _fadeEnd = end;
          });
        }
      });
    }
    return false;
  }

  @override
  void didUpdateWidget(TimelineToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new set of tools starts at its first item.
    final oldIds = oldWidget.items.map((i) => i.id).join(',');
    final newIds = widget.items.map((i) => i.id).join(',');
    if (oldIds != newIds && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final row = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = widget.items.length;
            // Spread items when they fit, scroll when they do not.
            final itemWidth = count == 0
                ? 64.0
                : (constraints.maxWidth / count).clamp(58.0, 84.0);
            return MouseDragScroll(
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final item in widget.items)
                        _ToolButton(
                          key: item.key ?? Key('timeline_tool_${item.id}'),
                          item: item,
                          width: itemWidth,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final faded = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          _fadeStart ? const Color(0x00000000) : const Color(0xff000000),
          const Color(0xff000000),
          const Color(0xff000000),
          _fadeEnd ? const Color(0x00000000) : const Color(0xff000000),
        ],
        stops: const [0, .08, .92, 1],
      ).createShader(bounds),
      child: row,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        child: SizedBox(
          height: TimelineToolbar.height,
          child: EditorGlassSurface(
            style: EditorGlassStyle.clear,
            borderRadius: TimelineToolbar.height / 2,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                if (widget.onBack != null) ...[
                  AppTooltip(
                    message: widget.backLabel,
                    child: Semantics(
                      button: true,
                      label: widget.backLabel,
                      excludeSemantics: true,
                      child: CupertinoButton(
                        key: const Key('timeline_tool_back'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 54),
                        onPressed: widget.onBack,
                        child: const Icon(
                          CupertinoIcons.chevron_back,
                          size: 22,
                          color: TimelineColors.text,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: .5,
                    height: 30,
                    color: TimelineColors.stroke,
                  ),
                ],
                Expanded(child: faded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({super.key, required this.item, required this.width});

  final TimelineToolItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final enabled = item.onPressed != null;
    final base = item.destructive ? TimelineColors.danger : TimelineColors.text;
    final color = enabled ? base : base.withValues(alpha: .34);
    return AppTooltip(
      message: item.label,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: item.active,
        label: item.label,
        hint: item.hint,
        excludeSemantics: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 54),
          pressedOpacity: .55,
          onPressed: item.onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width, minHeight: 54),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                height: 50,
                constraints: BoxConstraints(minWidth: width - 6),
                decoration: item.active
                    ? BoxDecoration(
                        color: const Color(0x2effffff),
                        borderRadius: BorderRadius.circular(25),
                      )
                    : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: 21, color: color),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: item.active
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
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
