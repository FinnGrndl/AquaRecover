import '../../core/models/media_kind.dart';
import '../../core/models/restoration_settings.dart';

typedef SettingValueReader = double Function(RestorationSettings settings);
typedef SettingValueWriter =
    RestorationSettings Function(RestorationSettings settings, double value);

enum EditorToolGroup { presets, light, color, details, effects, compare, video }

extension EditorToolGroupX on EditorToolGroup {
  String get label => switch (this) {
    EditorToolGroup.presets => 'Presets',
    EditorToolGroup.light => 'Light',
    EditorToolGroup.color => 'Color',
    EditorToolGroup.details => 'Details',
    EditorToolGroup.effects => 'Effects',
    EditorToolGroup.compare => 'Compare',
    EditorToolGroup.video => 'Video',
  };

  String get subtitle => switch (this) {
    EditorToolGroup.presets => 'One-tap underwater looks',
    EditorToolGroup.light => 'Exposure, contrast, and tone',
    EditorToolGroup.color => 'Water cast and color balance',
    EditorToolGroup.details => 'Haze, clarity, and sharpening',
    EditorToolGroup.effects => 'Vignette and LUT finishing',
    EditorToolGroup.compare => 'Original and adjusted preview',
    EditorToolGroup.video => 'Trim and raw frame settings',
  };

  bool isAvailableFor(MediaKind kind) {
    return this != EditorToolGroup.video || kind.isVideo;
  }

  List<AdjustmentControl> get adjustments => switch (this) {
    EditorToolGroup.light => [
      AdjustmentControl(
        id: 'recovery',
        label: 'Overall strength',
        value: (settings) => settings.recovery,
        apply: (settings, value) => settings.asPro(recovery: value),
        min: 0,
        max: 1.5,
        divisions: 30,
        help: 'Higher values add stronger water-cast correction.',
      ),
      AdjustmentControl(
        id: 'contrast_stretch',
        label: 'Contrast stretch',
        value: (settings) => settings.contrastStretch,
        apply: (settings, value) => settings.asPro(contrastStretch: value),
        min: 0,
        max: 1,
        divisions: 20,
      ),
      AdjustmentControl(
        id: 'contrast',
        label: 'Contrast',
        value: (settings) => settings.contrast,
        apply: (settings, value) => settings.asPro(contrast: value),
        min: .7,
        max: 1.6,
        divisions: 45,
      ),
      AdjustmentControl(
        id: 'gamma',
        label: 'Gamma',
        value: (settings) => settings.gamma,
        apply: (settings, value) => settings.asPro(gamma: value),
        min: .75,
        max: 1.35,
        divisions: 30,
      ),
      AdjustmentControl(
        id: 'brightness',
        label: 'Brightness',
        value: (settings) => settings.brightness,
        apply: (settings, value) => settings.asPro(brightness: value),
        min: -.5,
        max: .5,
        divisions: 40,
      ),
      AdjustmentControl(
        id: 'exposure',
        label: 'Exposure',
        value: (settings) => settings.exposure,
        apply: (settings, value) => settings.asPro(exposure: value),
        min: -.5,
        max: .5,
        divisions: 40,
      ),
      AdjustmentControl(
        id: 'highlights',
        label: 'Highlights',
        value: (settings) => settings.highlights,
        apply: (settings, value) => settings.asPro(highlights: value),
        min: -.6,
        max: .6,
        divisions: 48,
      ),
      AdjustmentControl(
        id: 'shadows',
        label: 'Shadows',
        value: (settings) => settings.shadows,
        apply: (settings, value) => settings.asPro(shadows: value),
        min: -.6,
        max: .6,
        divisions: 48,
      ),
      AdjustmentControl(
        id: 'black_point',
        label: 'Black point',
        value: (settings) => settings.blackPoint,
        apply: (settings, value) => settings.asPro(blackPoint: value),
        min: 0,
        max: .5,
        divisions: 30,
      ),
    ],
    EditorToolGroup.color => [
      AdjustmentControl(
        id: 'red_recovery',
        label: 'Red recovery',
        value: (settings) => settings.redRecovery,
        apply: (settings, value) => settings.asPro(redRecovery: value),
        min: 0,
        max: 2.5,
        divisions: 50,
        help: 'Restores colors absorbed by depth.',
      ),
      AdjustmentControl(
        id: 'auto_white_balance',
        label: 'Auto white balance',
        value: (settings) => settings.autoWhiteBalance,
        apply: (settings, value) => settings.asPro(autoWhiteBalance: value),
        min: 0,
        max: 1,
        divisions: 20,
      ),
      AdjustmentControl(
        id: 'saturation',
        label: 'Saturation',
        value: (settings) => settings.saturation,
        apply: (settings, value) => settings.asPro(saturation: value),
        min: .6,
        max: 2.2,
        divisions: 64,
      ),
      AdjustmentControl(
        id: 'vibrance',
        label: 'Vibrance',
        value: (settings) => settings.vibrance,
        apply: (settings, value) => settings.asPro(vibrance: value),
        min: 0,
        max: 1,
        divisions: 20,
      ),
      AdjustmentControl(
        id: 'hue',
        label: 'Hue',
        value: (settings) => settings.hue,
        apply: (settings, value) => settings.asPro(hue: value),
        min: -.25,
        max: .25,
        divisions: 50,
        help:
            'Small hue rotations help match strobes, filters, and water type.',
      ),
      AdjustmentControl(
        id: 'highlight_protection',
        label: 'Highlight protection',
        value: (settings) => settings.highlightProtection,
        apply: (settings, value) => settings.asPro(highlightProtection: value),
        min: 0,
        max: 1,
        divisions: 20,
      ),
    ],
    EditorToolGroup.details => [
      AdjustmentControl(
        id: 'haze_reduction',
        label: 'Haze reduction',
        value: (settings) => settings.hazeReduction,
        apply: (settings, value) => settings.asPro(hazeReduction: value),
        min: 0,
        max: 1,
        divisions: 20,
      ),
      AdjustmentControl(
        id: 'clarity',
        label: 'Clarity',
        value: (settings) => settings.clarity,
        apply: (settings, value) => settings.asPro(clarity: value),
        min: 0,
        max: 1,
        divisions: 20,
      ),
      AdjustmentControl(
        id: 'sharpness',
        label: 'Sharpness',
        value: (settings) => settings.sharpness,
        apply: (settings, value) => settings.asPro(sharpness: value),
        min: 0,
        max: 1,
        divisions: 20,
      ),
    ],
    EditorToolGroup.effects => [
      AdjustmentControl(
        id: 'vignette',
        label: 'Vignette',
        value: (settings) => settings.vignette,
        apply: (settings, value) => settings.asPro(vignette: value),
        min: 0,
        max: 1,
        divisions: 20,
      ),
    ],
    _ => const [],
  };
}

enum EditorCompareMode { edited, original, split }

extension EditorCompareModeX on EditorCompareMode {
  String get label => switch (this) {
    EditorCompareMode.edited => 'Edited',
    EditorCompareMode.original => 'Original',
    EditorCompareMode.split => 'Split',
  };
}

class AdjustmentControl {
  const AdjustmentControl({
    required this.id,
    required this.label,
    required this.value,
    required this.apply,
    required this.min,
    required this.max,
    this.divisions,
    this.help,
    this.format,
  });

  final String id;
  final String label;
  final SettingValueReader value;
  final SettingValueWriter apply;
  final double min;
  final double max;
  final int? divisions;
  final String? help;
  final String Function(double value)? format;
}

List<EditorToolGroup> activeEditorToolGroupsFor(MediaKind kind) {
  return [
    for (final group in EditorToolGroup.values)
      if (group.isAvailableFor(kind)) group,
  ];
}

const editorPresetChoices = [
  RestorationPreset.auto,
  RestorationPreset.vivid,
  RestorationPreset.deep,
  RestorationPreset.natural,
  RestorationPreset.shallow,
  RestorationPreset.greenWater,
  RestorationPreset.macro,
  RestorationPreset.redFilter,
  RestorationPreset.artificialLight,
];
