import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../timeline_controller.dart';
import '../../timeline_theme.dart';

/// Shared building blocks of the movie editor's tool panels: a header row
/// that shares the panel's close chevron, labelled sliders that undo in one
/// step per drag, neutral segmented controls, and choice tiles that show
/// their state with a fill and a checkmark rather than colour alone.

/// Neutral thumb of segmented controls on the dark glass (the system's dark
/// `tertiarySystemFill` look), so blue stays reserved for the primary action.
const toolSegmentThumb = Color(0xff636366);

/// The 44 pt row at the top of every tool panel: the tool's name on the
/// leading side and an optional action (Reset, Done) on the trailing side.
/// The panel's close chevron sits in the middle of the same row.
class ToolHeader extends StatelessWidget {
  const ToolHeader({
    super.key,
    required this.title,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  text: title,
                  children: [
                    if (subtitle != null)
                      TextSpan(
                        text: '  $subtitle',
                        style: const TextStyle(
                          color: TimelineColors.secondaryText,
                          fontWeight: FontWeight.w400,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TimelineColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // Keeps the centre free for the panel's chevron.
          const SizedBox(width: 64),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: trailing ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain text button for panel headers, such as Reset or Done.
class ToolTextButton extends StatelessWidget {
  const ToolTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.bold = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? TimelineColors.secondaryText.withValues(alpha: .4)
        : destructive
        ? TimelineColors.danger
        : TimelineColors.text;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(
        kMinInteractiveDimensionCupertino,
        kMinInteractiveDimensionCupertino,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

/// A slider with its label and value above it. One drag is one undo step:
/// it opens a gesture on the controller when the drag starts and closes it
/// when it ends.
class ToolSlider extends StatelessWidget {
  const ToolSlider({
    super.key,
    required this.controller,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    this.divisions,
    this.enabled = true,
    this.semanticsValue,
  });

  final TimelineController controller;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String valueLabel;
  final String? semanticsValue;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TimelineColors.secondaryText,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: TimelineColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Semantics(
            label: label,
            value: semanticsValue ?? valueLabel,
            child: SizedBox(
              height: 40,
              child: CupertinoSlider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                activeColor: TimelineColors.text,
                thumbColor: CupertinoColors.white,
                onChangeStart: enabled
                    ? (_) => controller.beginGesture()
                    : null,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? (_) => controller.endGesture() : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled row holding a control on the trailing side, such as a switch.
class ToolRow extends StatelessWidget {
  const ToolRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: TimelineColors.text, fontSize: 15),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A sliding segmented control in the editor's neutral style, optionally
/// with a label column on the leading side.
class ToolSegmented<T extends Object> extends StatelessWidget {
  const ToolSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.labelWidth = 44,
  });

  final T? value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String? label;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final control = CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      backgroundColor: TimelineColors.fill,
      thumbColor: toolSegmentThumb,
      padding: const EdgeInsets.all(3),
      children: {
        for (final entry in options.entries)
          entry.key: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Text(
              entry.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: TimelineColors.text,
                fontSize: 13,
                fontWeight: entry.key == value
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
      },
      onValueChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
    if (label == null) return control;
    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label!,
            style: const TextStyle(
              color: TimelineColors.secondaryText,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: control),
      ],
    );
  }
}

/// A square choice tile: a preview or symbol, a label under it, and, when
/// selected, a neutral fill, a white outline, and a checkmark badge.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
    this.preview,
    this.width = 76,
    this.focused = false,
    this.hint,
  });

  final String label;
  final bool selected;

  /// Draws a thicker outline: the tile whose settings show below.
  final bool focused;
  final IconData? icon;
  final Widget? preview;
  final double width;
  final String? hint;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      hint: hint,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Opacity(
          opacity: enabled ? 1 : .4,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 52,
                      width: width - 8,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0x33ffffff)
                            : TimelineColors.fill,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? CupertinoColors.white
                              : TimelineColors.stroke,
                          width: selected ? (focused ? 2.5 : 1.5) : .5,
                        ),
                      ),
                      child:
                          preview ??
                          Icon(icon, size: 22, color: TimelineColors.text),
                    ),
                    if (selected)
                      const Positioned(right: -4, top: -4, child: CheckBadge()),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TimelineColors.text,
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

/// A small white disc with a black checkmark.
class CheckBadge extends StatelessWidget {
  const CheckBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        shape: BoxShape.circle,
        border: Border.all(color: CupertinoColors.black, width: 1),
      ),
      child: Icon(
        CupertinoIcons.checkmark_alt,
        size: size * .72,
        color: CupertinoColors.black,
      ),
    );
  }
}

/// A full-width action row in a panel: a symbol, a label, and an optional
/// detail line, at least 44 pt tall.
class ToolActionRow extends StatelessWidget {
  const ToolActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled
        ? TimelineColors.text
        : TimelineColors.secondaryText.withValues(alpha: .45);
    return Semantics(
      button: true,
      enabled: enabled,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        minimumSize: const Size(0, 48),
        onPressed: onPressed,
        child: Row(
          children: [
            SizedBox(width: 28, child: Icon(icon, size: 20, color: color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 15)),
                  if (detail != null)
                    Text(
                      detail!,
                      style: const TextStyle(
                        color: TimelineColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A hairline between groups in a panel.
class ToolSeparator extends StatelessWidget {
  const ToolSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: .5,
    margin: const EdgeInsets.symmetric(vertical: 6),
    color: TimelineColors.stroke,
  );
}

/// A centred note for a panel with nothing to edit.
class ToolEmptyNote extends StatelessWidget {
  const ToolEmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: TimelineColors.secondaryText, fontSize: 13),
    ),
  );
}

/// A light tick when a value lands on a detent or snap point.
void snapHaptic() => HapticFeedback.selectionClick();

/// "1.5 s"-style seconds.
String secondsLabel(double seconds) =>
    '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';

/// "75 %"-style percentages.
String percentLabel(double value) => '${(value * 100).round()} %';

/// A tool panel's layout: the [ToolHeader] and, under it, the controls,
/// which scroll when the panel is short.
class ToolPanelBody extends StatelessWidget {
  const ToolPanelBody({
    super.key,
    required this.header,
    required this.children,
  });

  final ToolHeader header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            children: children,
          ),
        ),
      ],
    );
  }
}

/// The selected clip, overlay, or sound as a short name for panel headers.
String selectionName(TimelineController controller) {
  final selection = controller.selection;
  switch (selection) {
    case ClipSelection(:final id):
      final index = controller.project.clips.indexWhere((c) => c.id == id);
      final clip = controller.clipById(id);
      return '${clip?.isVideo ?? false ? 'Clip' : 'Photo'} ${index + 1}';
    case OverlaySelection(:final id):
      final overlay = controller.overlayById(id);
      if (overlay?.title != null) return 'Title';
      return overlay?.isVideo ?? false ? 'Video overlay' : 'Photo overlay';
    case AudioSelection(:final id):
      final audio = controller.audioById(id);
      return audio == null || audio.name.isEmpty ? 'Sound' : audio.name;
    case NoSelection():
      return '';
  }
}
