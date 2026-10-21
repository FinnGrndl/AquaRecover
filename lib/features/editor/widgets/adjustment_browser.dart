import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../core/models/restoration_settings.dart';
import '../../../shared/reduce_motion.dart';
import '../editor_tools.dart';
import 'setting_slider.dart';
import '../../../shared/widgets/mouse_drag_scroll.dart';

/// Apple Photos-inspired adjustment browser: every current value stays visible
/// in one horizontal strip while the selected value gets a precise slider.
///
/// Tapping a value only selects it. Reset restores the selected value to the
/// preset's, so choosing a control never throws away an adjustment.
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
    this.trailing,
  });

  final List<AdjustmentControl> controls;
  final RestorationSettings settings;
  final RestorationSettings presetSettings;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final ValueChanged<RestorationSettings> onChanged;
  final bool enabled;

  /// Optional action shown next to the hint, such as the white balance
  /// picker.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final active = controls.firstWhere(
      (control) => control.id == selectedId,
      orElse: () => controls.first,
    );
    final presetValue = active.value(presetSettings);
    final canReset =
        enabled && (active.value(settings) - presetValue).abs() > 1e-9;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // At large text sizes the buttons move below the hint instead of
        // squeezing it. The full width keeps them trailing otherwise.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Tap a value to adjust it',
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel,
                    context,
                  ),
                  fontSize: 11,
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ?trailing,
                  CupertinoButton(
                    key: const Key('adjustment_reset'),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(
                      kMinInteractiveDimensionCupertino,
                      kMinInteractiveDimensionCupertino,
                    ),
                    onPressed: canReset
                        ? () => onChanged(active.apply(settings, presetValue))
                        : null,
                    child: Text(
                      'Reset',
                      semanticsLabel: 'Reset ${active.label}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _AdjustmentValueButton.stripHeight(
            MediaQuery.textScalerOf(context),
          ),
          child: MouseDragScroll(
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
                  onPressed: () => onSelected(control.id),
                );
              },
            ),
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

  static const _topGap = 6.0;
  static const _circleSize = 38.0;
  static const _labelGap = 5.0;
  static const _labelSize = 11.0;

  /// Caption 2 leading: 13 pt lines for 11 pt text.
  static const _labelLineHeight = 13 / 11;

  /// Fits the circle and a two-line label at the current text size, so a
  /// larger Dynamic Type size grows the strip instead of clipping labels.
  static double stripHeight(TextScaler scaler) => math.max(
    82,
    _topGap +
        _circleSize +
        _labelGap +
        2 * scaler.scale(_labelSize) * _labelLineHeight +
        1,
  );

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
          // Top-aligned so the circles stay in line when a label wraps.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: _topGap),
              AnimatedContainer(
                duration: motionDuration(
                  context,
                  const Duration(milliseconds: 160),
                ),
                width: _circleSize,
                height: _circleSize,
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
              const SizedBox(height: _labelGap),
              Text(
                control.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: foreground,
                  fontSize: _labelSize,
                  height: _labelLineHeight,
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
