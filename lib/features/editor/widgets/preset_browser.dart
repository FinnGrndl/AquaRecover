import 'package:flutter/cupertino.dart';

import '../../../core/models/restoration_settings.dart';
import '../../../core/processing/scene_analyzer.dart';
import '../editor_tools.dart';
import 'setting_slider.dart';

/// Selects a starting profile before individual adjustments are applied.
class PresetBrowser extends StatelessWidget {
  const PresetBrowser({
    super.key,
    required this.settings,
    required this.onChanged,
    this.enabled = true,
    this.suggestion,
  });

  final RestorationSettings settings;
  final ValueChanged<RestorationSettings> onChanged;
  final bool enabled;

  /// What the scene analysis suggests for the selected photo, if anything.
  final SceneAnalysis? suggestion;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (suggestion case final suggestion?)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SuggestionCard(
              suggestion: suggestion,
              applied: _isApplied(suggestion),
              onApply: enabled
                  ? () => onChanged(
                      suggestion.suggestedSettings.copyWith(
                        jpegQuality: settings.jpegQuality,
                      ),
                    )
                  : null,
            ),
          ),
        SizedBox(
          height: kMinInteractiveDimensionCupertino,
          child: ListView.separated(
            key: const Key('preset_list'),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemCount: editorPresetChoices.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final preset = editorPresetChoices[index];
              return _PresetButton(
                preset: preset,
                selected: settings.preset == preset,
                suggested: suggestion?.suggestedPreset == preset,
                enabled: enabled,
                onPressed: () {
                  final strength = preset == RestorationPreset.none
                      ? 0.0
                      : settings.preset == RestorationPreset.none
                      ? 1.0
                      : settings.presetStrength;
                  onChanged(
                    preset
                        .settingsAtStrength(strength)
                        .copyWith(jpegQuality: settings.jpegQuality),
                  );
                },
              );
            },
          ),
        ),
        SettingSlider(
          key: const Key('preset_strength'),
          label: 'Preset strength',
          value: settings.preset == RestorationPreset.none
              ? 0
              : settings.presetStrength,
          min: 0,
          max: 1,
          divisions: 20,
          format: (value) => '${(value * 100).round()}%',
          help: settings.preset == RestorationPreset.none
              ? 'None leaves the image unchanged. Choose another preset to adjust its strength.'
              : 'Scales the selected preset while keeping later manual adjustments.',
          onChanged: enabled && settings.preset != RestorationPreset.none
              ? (value) => onChanged(settings.withPresetStrength(value))
              : null,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                CupertinoIcons.info_circle,
                size: 15,
                color: secondary,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${settings.preset.label}: ${settings.preset.help}',
                style: textStyle.copyWith(fontSize: 13, color: secondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isApplied(SceneAnalysis suggestion) =>
      settings.preset == suggestion.suggestedPreset &&
      (settings.presetStrength - suggestion.suggestedStrength).abs() < .015;
}

/// Offers the analyzed preset for the photo with a one-line reason.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.applied,
    required this.onApply,
  });

  final SceneAnalysis suggestion;
  final bool applied;
  final VoidCallback? onApply;

  static String waterLabel(WaterType water) => switch (water) {
    WaterType.blue => 'Blue water',
    WaterType.green => 'Green water',
    WaterType.neutral => 'Little color cast',
  };

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final preset = suggestion.suggestedPreset;
    final strength = (suggestion.suggestedStrength * 100).round();
    final reason = suggestion.reasons.isEmpty ? null : suggestion.reasons.first;
    return Semantics(
      container: true,
      label:
          '${waterLabel(suggestion.waterType)}. Suggested ${preset.label} '
          'at $strength percent.',
      // A neutral card, so the Apply button stays the only tinted control.
      child: Container(
        key: const Key('preset_suggestion'),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemFill,
            context,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.wand_stars, size: 20, color: secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${waterLabel(suggestion.waterType)}: '
                    '${preset.label} $strength%',
                    style: textStyle.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (reason != null)
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle.copyWith(fontSize: 12, color: secondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            CupertinoButton(
              key: const Key('apply_preset_suggestion'),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size.square(kMinInteractiveDimensionCupertino),
              borderRadius: BorderRadius.circular(99),
              color: applied ? null : primary,
              onPressed: applied ? null : onApply,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (applied) ...[
                    Icon(CupertinoIcons.checkmark, size: 15, color: secondary),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    applied ? 'Applied' : 'Apply',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: applied ? secondary : CupertinoColors.white,
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

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.selected,
    required this.suggested,
    required this.enabled,
    required this.onPressed,
  });

  final RestorationPreset preset;
  final bool selected;
  final bool suggested;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.label} preset${suggested ? ', suggested' : ''}',
      hint: preset.help,
      // The chip keeps its compact capsule; the button around it keeps the
      // 44 pt hit region.
      child: CupertinoButton(
        key: Key('preset_${preset.name}'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(
          kMinInteractiveDimensionCupertino,
          kMinInteractiveDimensionCupertino,
        ),
        onPressed: enabled ? onPressed : null,
        // Dimmed, not recolored, so the selected preset still shows while
        // the chips are disabled.
        child: Opacity(
          opacity: enabled ? 1 : .5,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: selected
                  ? primary
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemFill,
                      context,
                    ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (suggested) ...[
                    Icon(
                      CupertinoIcons.wand_stars,
                      size: 13,
                      color: selected ? CupertinoColors.white : primary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    preset.label,
                    style: TextStyle(
                      color: selected
                          ? CupertinoColors.white
                          : CupertinoDynamicColor.resolve(
                              CupertinoColors.label,
                              context,
                            ),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
