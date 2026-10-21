import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../shared/widgets/mouse_drag_scroll.dart';

/// The built-in effects for the selected clip or overlay (or the clip under
/// the playhead from the root toolbar): a category switcher, a row of tiles
/// that toggle effects, and the intensity of the focused effect.
class EffectsPanel extends StatefulWidget {
  const EffectsPanel({super.key, required this.controller});

  final TimelineController controller;

  static IconData iconFor(EffectType type) => switch (type) {
    EffectType.mono => CupertinoIcons.circle_lefthalf_fill,
    EffectType.sepia => CupertinoIcons.sun_haze,
    EffectType.cyanotype => CupertinoIcons.drop,
    EffectType.deepBlue => CupertinoIcons.drop_fill,
    EffectType.vivid => CupertinoIcons.sparkles,
    EffectType.faded => CupertinoIcons.film,
    EffectType.softFocus => CupertinoIcons.eye,
    EffectType.clarity => CupertinoIcons.scope,
    EffectType.grain => CupertinoIcons.circle_grid_3x3,
    EffectType.vignette => CupertinoIcons.circle,
    EffectType.cinemaBars => CupertinoIcons.rectangle_split_3x1,
    EffectType.sunRays => CupertinoIcons.rays,
    EffectType.caustics => CupertinoIcons.waveform_path,
    EffectType.strobe => CupertinoIcons.bolt,
    EffectType.swell => CupertinoIcons.wind,
    EffectType.drift => CupertinoIcons.arrow_up_left_arrow_down_right,
  };

  @override
  State<EffectsPanel> createState() => _EffectsPanelState();
}

class _EffectsPanelState extends State<EffectsPanel> {
  EffectCategory? _category;
  EffectType? _focused;

  TimelineController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final target = _controller.effectTarget;
    final onOverlay = target is OverlaySelection;
    final categories = [
      for (final category in EffectCategory.values)
        if (EffectType.inCategory(
          category,
        ).any((t) => !onOverlay || t.overlayAllowed))
          category,
    ];
    final effects = _controller.targetEffects;
    final category = categories.contains(_category)
        ? _category!
        : categories.first;
    final types = [
      for (final t in EffectType.inCategory(category))
        if (!onOverlay || t.overlayAllowed) t,
    ];
    ClipEffect? focused;
    for (final e in effects) {
      if (e.type == _focused) focused = e;
    }
    final targetName = switch (target) {
      ClipSelection(:final id) =>
        '${_controller.clipById(id)?.isVideo ?? false ? 'Clip' : 'Photo'} '
            '${_controller.project.clips.indexWhere((c) => c.id == id) + 1}',
      OverlaySelection() => selectionName(_controller),
      _ => null,
    };
    return ToolPanelBody(
      header: ToolHeader(
        title: 'Effects',
        subtitle: targetName == null
            ? null
            : effects.isEmpty
            ? targetName
            : '$targetName · ${effects.length} on',
      ),
      children: [
        if (target.isNone)
          const ToolEmptyNote('Add a clip first, then give it an effect.')
        else ...[
          ToolSegmented<EffectCategory>(
            value: category,
            options: {
              for (final c in categories)
                c: c == EffectCategory.look ? 'Looks' : c.label,
            },
            onChanged: (c) => setState(() => _category = c),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: MouseDragScroll(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(top: 4),
                children: [
                  for (final type in types)
                    _tile(type, effects.any((e) => e.type == type)),
                ],
              ),
            ),
          ),
          if (focused != null) ...[
            const SizedBox(height: 6),
            ToolSlider(
              key: const Key('timeline_effect_intensity'),
              controller: _controller,
              label: '${focused.type.label} intensity',
              value: focused.intensity,
              min: 0,
              max: 1,
              valueLabel: percentLabel(focused.intensity),
              onChanged: (v) =>
                  _controller.setEffectIntensity(focused!.type, v),
            ),
            Row(
              children: [
                ToolTextButton(
                  label: 'Reset',
                  onPressed: focused.intensity == focused.type.defaultIntensity
                      ? null
                      : () => _controller.setEffectIntensity(
                          focused!.type,
                          focused.type.defaultIntensity,
                        ),
                ),
                const Spacer(),
                ToolTextButton(
                  key: const Key('timeline_effect_remove'),
                  label: 'Remove',
                  destructive: true,
                  onPressed: () {
                    _controller.removeEffect(focused!.type);
                    setState(() => _focused = null);
                  },
                ),
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Tap an effect to add it. Tap it again to adjust or remove it.',
                style: TextStyle(
                  color: TimelineColors.secondaryText,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _tile(EffectType type, bool on) {
    final isFocused = on && _focused == type;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceTile(
        key: Key('timeline_effect_${type.id}'),
        label: type.label,
        selected: on,
        focused: isFocused,
        hint: on
            ? (isFocused ? 'Removes the effect' : 'Shows its intensity')
            : 'Adds the effect',
        preview: _EffectPreview(type: type),
        onPressed: () => setState(() {
          if (!on) {
            _controller.toggleEffect(type);
            _focused = type;
          } else if (!isFocused) {
            _focused = type;
          } else {
            _controller.toggleEffect(type);
            _focused = null;
          }
        }),
      ),
    );
  }
}

/// A small swatch of underwater colours. Colour effects show their real
/// colour matrix on it, so the tile is a live preview; the others show their
/// symbol.
class _EffectPreview extends StatelessWidget {
  const _EffectPreview({required this.type});

  final EffectType type;

  static const _swatch = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff2fb5c9), Color(0xff0b5d84), Color(0xffd9a46a)],
        stops: [0, .55, 1],
      ),
    ),
    child: SizedBox.expand(),
  );

  @override
  Widget build(BuildContext context) {
    if (type.kind == EffectKind.colorMatrix) {
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(
          ColorMatrices.withByteOffsets(ColorMatrices.full(type)),
        ),
        child: _swatch,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const Opacity(opacity: .45, child: _swatch),
        Icon(EffectsPanel.iconFor(type), size: 22, color: TimelineColors.text),
      ],
    );
  }
}
