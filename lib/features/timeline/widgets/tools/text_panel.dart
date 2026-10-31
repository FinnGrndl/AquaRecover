import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../shared/widgets/mouse_drag_scroll.dart';
import '../../../../shared/widgets/app_tooltip.dart';
import '../../../../l10n/timeline_labels.dart';
import '../../../../l10n/l10n.dart';

/// Edits the selected title: the text in a multi-line field (above the
/// keyboard), a style, a colour, the alignment, and the size. Typing until
/// the field loses focus is one undo step.
class TextPanel extends StatefulWidget {
  const TextPanel({
    super.key,
    required this.controller,
    required this.overlayId,
    required this.onDone,
    this.autofocus = false,
    this.today,
  });

  final TimelineController controller;
  final String overlayId;
  final VoidCallback onDone;
  final bool autofocus;

  /// The date a Dive stamp shows; today unless a test fixes it.
  final DateTime? today;

  /// Text colours: white, sand, coral, yellow, aqua, black.
  static List<(int, String)> swatchesIn(AppLocalizations l10n) => [
    (0xFFFFFFFF, l10n.colorWhite),
    (0xFFE8DCC0, l10n.colorSand),
    (0xFFFF7F6B, l10n.colorCoral),
    (0xFFFFD60A, l10n.colorYellow),
    (0xFF64D2FF, l10n.colorAqua),
    (0xFF000000, l10n.colorBlack),
  ];

  static String styleLabel(AppLocalizations l10n, TitleStyle style) =>
      style == TitleStyle.boldBox
      ? l10n.titleStyleBoldBox
      : style.labelIn(l10n);

  /// The date a Dive stamp shows, such as "Oct 19, 2026" or "19.10.2026".
  static String dateLabel(AppLocalizations l10n, DateTime date) =>
      l10n.mediumDate(date);

  @override
  State<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends State<TextPanel> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  bool _editing = false;

  TimelineController get _controller => widget.controller;
  TimelineOverlay? get _overlay => _controller.overlayById(widget.overlayId);

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _overlay?.title?.text ?? '');
    if (widget.autofocus) {
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    }
    _focus.addListener(_onFocus);
    _controller.addListener(_sync);
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _focus.removeListener(_onFocus);
    if (_editing) _controller.endGesture(notify: false);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus && !_editing) {
      _editing = true;
      _controller.beginGesture();
    } else if (!_focus.hasFocus && _editing) {
      _editing = false;
      _controller.endGesture();
    }
  }

  /// Keeps the field in step with undo and redo.
  void _sync() {
    final text = _overlay?.title?.text;
    if (text != null && text != _text.text && !_focus.hasFocus) {
      _text.text = text;
    }
  }

  void _update(TitleSpec Function(TitleSpec title) change) {
    final title = _overlay?.title;
    if (title == null) return;
    _controller.updateTitle(widget.overlayId, change(title));
  }

  void _setStyle(TitleStyle style) {
    final title = _overlay?.title;
    if (title == null) return;
    var text = title.text;
    if (style == TitleStyle.diveStamp &&
        !text.contains('\n') &&
        (text.trim().isEmpty ||
            text == 'Title' ||
            text == context.l10n.defaultTitleText)) {
      text =
          '${_controller.project.name}\n'
          '${TextPanel.dateLabel(context.l10n, widget.today ?? DateTime.now())}';
      _text.text = text;
    }
    _update((t) => t.copyWith(style: style, text: text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final overlay = _overlay;
    final title = overlay?.title;
    final header = ToolHeader(
      title: l10n.toolText,
      trailing: ToolTextButton(
        key: const Key('timeline_text_done'),
        label: l10n.done,
        bold: true,
        onPressed: () {
          _focus.unfocus();
          widget.onDone();
        },
      ),
    );
    if (overlay == null || title == null) {
      return ToolPanelBody(
        header: header,
        children: [ToolEmptyNote(l10n.selectTitleToEdit)],
      );
    }
    final size = _controller.titleSize(overlay);
    return ToolPanelBody(
      header: header,
      children: [
        CupertinoTextField(
          key: const Key('timeline_text_field'),
          controller: _text,
          focusNode: _focus,
          autofocus: widget.autofocus,
          minLines: 1,
          maxLines: 3,
          keyboardAppearance: Brightness.dark,
          textCapitalization: TextCapitalization.sentences,
          placeholder: l10n.defaultTitleText,
          placeholderStyle: const TextStyle(
            color: TimelineColors.secondaryText,
            fontSize: 17,
          ),
          style: const TextStyle(color: TimelineColors.text, fontSize: 17),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: TimelineColors.fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TimelineColors.stroke, width: .5),
          ),
          onChanged: (text) => _update((t) => t.copyWith(text: text)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: MouseDragScroll(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final style in TitleStyle.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _StyleChip(
                      key: Key('timeline_title_style_${style.name}'),
                      label: TextPanel.styleLabel(l10n, style),
                      selected: title.style == style,
                      onPressed: () => _setStyle(style),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Wraps in the narrow side panel of iPad and Mac windows rather than
        // pushing the last swatches out of view.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            for (final (color, name) in TextPanel.swatchesIn(l10n))
              _Swatch(
                color: Color(color),
                name: name,
                selected: title.color == color,
                onPressed: () => _update((t) => t.copyWith(color: color)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ToolSegmented<TitleAlign>(
          value: title.align,
          options: {
            TitleAlign.left: l10n.alignLeft,
            TitleAlign.center: l10n.alignCenter,
            TitleAlign.right: l10n.alignRight,
          },
          onChanged: (a) => _update((t) => t.copyWith(align: a)),
        ),
        const SizedBox(height: 8),
        ToolSlider(
          key: const Key('timeline_title_size'),
          controller: _controller,
          label: l10n.titleSize,
          value: size.clamp(0.03, 0.2).toDouble(),
          min: 0.03,
          max: 0.2,
          valueLabel: l10n.percentOfHeight((size * 100).round()),
          onChanged: (v) => _controller.setTitleSize(widget.overlayId, v),
        ),
      ],
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onPressed,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? CupertinoColors.white : TimelineColors.stroke,
                width: selected ? 1.5 : .5,
              ),
            ),
            color: selected ? const Color(0x33ffffff) : TimelineColors.fill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 14,
                  color: TimelineColors.text,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: TimelineColors.text,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = color.computeLuminance() < .2;
    return AppTooltip(
      message: name,
      child: Semantics(
        button: true,
        selected: selected,
        label: context.l10n.swatchText(name),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? CupertinoColors.white
                        : const Color(0x66ffffff),
                    width: selected ? 2.5 : .5,
                  ),
                ),
                child: selected
                    ? Icon(
                        CupertinoIcons.checkmark_alt,
                        size: 16,
                        color: dark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
