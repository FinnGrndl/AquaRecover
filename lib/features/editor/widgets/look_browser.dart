import 'package:flutter/cupertino.dart';

import '../../../core/models/restoration_settings.dart';
import '../editor_tools.dart';

/// Applies complete starting profiles without duplicating individual sliders.
class LookBrowser extends StatelessWidget {
  const LookBrowser({
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
          'Choose a look',
          style: textStyle.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'A look replaces all 19 adjustment values. Auto restores the balanced starting profile; moving any adjustment switches the result to Pro.',
          style: textStyle.copyWith(fontSize: 13, color: secondary),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final preset in editorPresetChoices) ...[
                _LookButton(
                  preset: preset,
                  selected: settings.preset == preset,
                  enabled: enabled,
                  onPressed: () => onChanged(preset.settings),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
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

class _LookButton extends StatelessWidget {
  const _LookButton({
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
      label: '${preset.label} look',
      hint: preset.help,
      child: CupertinoButton(
        key: Key('look_${preset.name}'),
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
