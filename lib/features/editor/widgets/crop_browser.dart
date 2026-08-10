import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;

import '../../../core/models/image_transform_settings.dart';
import 'setting_slider.dart';

class CropBrowser extends StatelessWidget {
  const CropBrowser({
    super.key,
    required this.settings,
    required this.sourceAspectRatio,
    required this.onChanged,
    this.enabled = true,
  });

  final ImageTransformSettings settings;
  final double sourceAspectRatio;
  final ValueChanged<ImageTransformSettings> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          key: const Key('crop_aspect_ratio_scroll'),
          scrollDirection: Axis.horizontal,
          child: CupertinoSlidingSegmentedControl<CropAspectRatio>(
            key: const Key('crop_aspect_ratio'),
            groupValue: settings.aspectRatio,
            backgroundColor: CupertinoColors.white.withValues(alpha: .10),
            thumbColor: CupertinoColors.activeBlue,
            children: {
              for (final aspect in CropAspectRatio.values)
                aspect: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    aspect.label,
                    style: const TextStyle(color: CupertinoColors.white),
                  ),
                ),
            },
            onValueChanged: (value) {
              if (enabled && value != null) {
                onChanged(
                  settings.copyWith(
                    aspectRatio: value,
                    customAspectRatio: value == CropAspectRatio.freeform
                        ? settings.outputAspectRatio(sourceAspectRatio)
                        : null,
                  ),
                );
              }
            },
          ),
        ),
        if (settings.aspectRatio == CropAspectRatio.freeform)
          SettingSlider(
            key: const Key('crop_freeform_ratio'),
            label: 'Freeform ratio',
            value: settings.customAspectRatio,
            min: .5,
            max: 2,
            divisions: 60,
            format: (value) => '${value.toStringAsFixed(2)}:1',
            onChanged: enabled
                ? (value) =>
                      onChanged(settings.copyWith(customAspectRatio: value))
                : null,
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CropIconButton(
              key: const Key('crop_rotate_left'),
              icon: CupertinoIcons.rotate_left,
              label: 'Rotate left',
              shortLabel: 'Left',
              enabled: enabled,
              onPressed: () => onChanged(
                settings.copyWith(
                  quarterTurns: settings.normalizedQuarterTurns + 3,
                ),
              ),
            ),
            _CropIconButton(
              key: const Key('crop_rotate_right'),
              icon: CupertinoIcons.rotate_right,
              label: 'Rotate right',
              shortLabel: 'Right',
              enabled: enabled,
              onPressed: () => onChanged(
                settings.copyWith(
                  quarterTurns: settings.normalizedQuarterTurns + 1,
                ),
              ),
            ),
            _CropIconButton(
              key: const Key('crop_flip_horizontal'),
              icon: CupertinoIcons.arrow_left_right,
              label: 'Flip horizontally',
              shortLabel: 'Flip H',
              selected: settings.flipHorizontal,
              enabled: enabled,
              onPressed: () => onChanged(
                settings.copyWith(flipHorizontal: !settings.flipHorizontal),
              ),
            ),
            _CropIconButton(
              key: const Key('crop_flip_vertical'),
              icon: CupertinoIcons.arrow_up_arrow_down,
              label: 'Flip vertically',
              shortLabel: 'Flip V',
              selected: settings.flipVertical,
              enabled: enabled,
              onPressed: () => onChanged(
                settings.copyWith(flipVertical: !settings.flipVertical),
              ),
            ),
            _CropIconButton(
              key: const Key('crop_reset'),
              icon: CupertinoIcons.arrow_counterclockwise,
              label: 'Reset crop',
              shortLabel: 'Reset',
              enabled: enabled && !settings.isIdentity,
              onPressed: () => onChanged(const ImageTransformSettings()),
            ),
          ],
        ),
        SettingSlider(
          key: const Key('crop_straighten'),
          label: 'Straighten',
          value: settings.straightenDegrees,
          min: -45,
          max: 45,
          divisions: 90,
          format: (value) => '${value.round()}°',
          onChanged: enabled
              ? (value) =>
                    onChanged(settings.copyWith(straightenDegrees: value))
              : null,
        ),
        SettingSlider(
          key: const Key('crop_zoom'),
          label: 'Zoom',
          value: settings.zoom,
          min: 1,
          max: 4,
          divisions: 60,
          format: (value) => '${value.toStringAsFixed(1)}x',
          showHeader: true,
          onChanged: enabled
              ? (value) => onChanged(settings.copyWith(zoom: value))
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.hand_draw, size: 14, color: secondary),
            const SizedBox(width: 6),
            Text(
              'Pinch to zoom and drag the image to reposition it.',
              style: CupertinoTheme.of(
                context,
              ).textTheme.textStyle.copyWith(fontSize: 12, color: secondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _CropIconButton extends StatelessWidget {
  const _CropIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.shortLabel,
    required this.enabled,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String shortLabel;
  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        selected: selected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(42, 42),
                borderRadius: BorderRadius.circular(99),
                color: selected
                    ? primary.withValues(alpha: .24)
                    : CupertinoDynamicColor.resolve(
                        CupertinoColors.secondarySystemFill,
                        context,
                      ),
                onPressed: enabled ? onPressed : null,
                child: Icon(
                  icon,
                  size: 19,
                  color: !enabled
                      ? CupertinoColors.systemGrey
                      : selected
                      ? primary
                      : CupertinoColors.white.withValues(alpha: .90),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                shortLabel,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: enabled
                      ? CupertinoColors.white.withValues(alpha: .72)
                      : CupertinoColors.systemGrey,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
