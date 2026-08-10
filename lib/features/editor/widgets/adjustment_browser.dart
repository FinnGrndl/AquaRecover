import 'package:flutter/cupertino.dart';

import '../../../core/models/restoration_settings.dart';
import '../editor_tools.dart';
import 'setting_slider.dart';

/// Apple Photos-inspired adjustment browser: every current value stays visible
/// in one horizontal strip while the selected value gets a precise slider.
class AdjustmentBrowser extends StatelessWidget {
  const AdjustmentBrowser({
    super.key,
    required this.controls,
    required this.settings,
    required this.presetSettings,
    required this.selectedId,
    required this.onSelected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<AdjustmentControl> controls;
  final RestorationSettings settings;
  final RestorationSettings presetSettings;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final ValueChanged<RestorationSettings> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = controls.firstWhere(
      (control) => control.id == selectedId,
      orElse: () => controls.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.center,
          child: Text(
            'Tap a value to restore the preset value',
            textAlign: TextAlign.center,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondaryLabel,
                context,
              ),
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 82,
          child: ListView.separated(
            key: const Key('all_adjustment_values'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: controls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) {
              final control = controls[index];
              final selected = control.id == active.id;
              return _AdjustmentValueButton(
                control: control,
                value: control.value(settings),
                selected: selected,
                enabled: enabled,
                onPressed: () {
                  onSelected(control.id);
                  onChanged(
                    control.apply(settings, control.value(presetSettings)),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SettingSlider(
          key: Key('active_adjustment_${active.id}'),
          label: active.label,
          value: active.value(settings),
          min: active.min,
          max: active.max,
          divisions: active.divisions,
          help: active.help,
          format: active.format,
          showHeader: false,
          showValue: false,
          onChanged: enabled
              ? (value) => onChanged(active.apply(settings, value))
              : null,
        ),
      ],
    );
  }
}

class _AdjustmentValueButton extends StatelessWidget {
  const _AdjustmentValueButton({
    required this.control,
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final AdjustmentControl control;
  final double value;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final foreground = selected ? accent : label;
    return Semantics(
      button: true,
      selected: selected,
      label: '${control.label}, ${_compactValue(control, value)}',
      hint: control.help,
      child: CupertinoButton(
        key: Key('adjustment_${control.id}'),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: enabled ? onPressed : null,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? accent.withValues(alpha: .16)
                      : CupertinoColors.transparent,
                  border: Border.all(
                    color: selected ? accent : secondary.withValues(alpha: .48),
                    width: selected ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _compactValue(control, value),
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                control.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: foreground,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _compactValue(AdjustmentControl control, double value) {
    final formatted = control.format?.call(value);
    if (formatted != null && formatted.length <= 5) return formatted;
    if (value == 0) return '0';
    final digits = value.abs() >= 10
        ? 0
        : value.abs() >= 1
        ? 1
        : 2;
    return value.toStringAsFixed(digits);
  }
}
