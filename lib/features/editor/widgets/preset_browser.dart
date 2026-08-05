import 'package:flutter/cupertino.dart';

import '../../../core/models/restoration_settings.dart';
import '../editor_tools.dart';
import 'setting_slider.dart';

/// Selects a starting profile before individual adjustments are applied.
class PresetBrowser extends StatelessWidget {
  const PresetBrowser({
    super.key,
    required this.settings,
    required this.onChanged,
    this.enabled = true,
  });

  final RestorationSettings settings;
  final ValueChanged<RestorationSettings> onChanged;
  final bool enabled;

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
        Text(
          'Choose a preset',
          style: textStyle.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Presets provide the starting values. Adjustments refine the selected preset without replacing it.',
          style: textStyle.copyWith(fontSize: 13, color: secondary),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
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
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final RestorationPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.label} preset',
      hint: preset.help,
      child: CupertinoButton(
        key: Key('preset_${preset.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        minimumSize: Size.zero,
        borderRadius: BorderRadius.circular(99),
        color: selected
            ? primary
            : CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemFill,
                context,
              ),
        onPressed: enabled ? onPressed : null,
        child: Text(
          preset.label,
          style: TextStyle(
            color: selected
                ? CupertinoColors.white
                : CupertinoDynamicColor.resolve(CupertinoColors.label, context),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
