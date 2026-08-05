import '../../core/models/media_kind.dart';
import '../../core/models/restoration_settings.dart';

typedef SettingValueReader = double Function(RestorationSettings settings);
typedef SettingValueWriter =
    RestorationSettings Function(RestorationSettings settings, double value);

enum EditorToolGroup { presets, light, color, details, effects, video }

extension EditorToolGroupX on EditorToolGroup {
  String get label => switch (this) {
    EditorToolGroup.presets => 'Presets',
    EditorToolGroup.light => 'Adjust',
    EditorToolGroup.color => 'Color',
    EditorToolGroup.details => 'Details',
    EditorToolGroup.effects => 'Finish',
    EditorToolGroup.video => 'Video',
  };

  String get subtitle => switch (this) {
    EditorToolGroup.presets => 'Starting profile and strength',
    EditorToolGroup.light => 'All image adjustments',
    EditorToolGroup.color => 'Water cast and color balance',
    EditorToolGroup.details => 'Haze, clarity, and sharpening',
    EditorToolGroup.effects => 'LUT and finishing options',
    EditorToolGroup.video => 'Trim and raw frame settings',
  };

  bool isAvailableFor(MediaKind kind) {
    return this != EditorToolGroup.video || kind.isVideo;
  }

  List<AdjustmentControl> get adjustments => switch (this) {
    EditorToolGroup.light => [
      AdjustmentControl(
        id: 'recovery',
        label: 'Water correction',
        value: (settings) => settings.recovery,
        apply: (settings, value) => settings.copyWith(recovery: value),
        min: 0,
        max: 1.5,
        divisions: 30,
        help:
            'Controls the underwater cast-recovery stage only. It strengthens color recovery and local neutralization, but does not scale exposure, contrast, saturation, or sharpening.',
        format: (value) => '${(value * 100).round()}%',
      ),
      AdjustmentControl(
        id: 'contrast_stretch',
        label: 'Contrast stretch',
        value: (settings) => settings.contrastStretch,
        apply: (settings, value) => settings.copyWith(contrastStretch: value),
        min: 0,
        max: 1,
        divisions: 20,
        help:
            'Expands the measured dark-to-bright range. High values can make murky scenes punchier but may clip detail.',
      ),
      AdjustmentControl(
        id: 'contrast',
        label: 'Contrast',
        value: (settings) => settings.contrast,
        apply: (settings, value) => settings.copyWith(contrast: value),
        min: .7,
        max: 1.6,
        divisions: 45,
        help:
            'Changes separation around the midtones without re-running the underwater color recovery.',
      ),
      AdjustmentControl(
        id: 'gamma',
        label: 'Gamma',
        value: (settings) => settings.gamma,
        apply: (settings, value) => settings.copyWith(gamma: value),
        min: .75,
        max: 1.35,
        divisions: 30,
        help:
            'Moves midtone brightness while keeping the black and white endpoints mostly fixed.',
      ),
      AdjustmentControl(
        id: 'brightness',
        label: 'Brightness',
        value: (settings) => settings.brightness,
        apply: (settings, value) => settings.copyWith(brightness: value),
        min: -.5,
        max: .5,
        divisions: 40,
        help:
            'Adds or removes a uniform amount of light after the main correction.',
      ),
      AdjustmentControl(
        id: 'exposure',
        label: 'Exposure',
        value: (settings) => settings.exposure,
        apply: (settings, value) => settings.copyWith(exposure: value),
        min: -.5,
        max: .5,
        divisions: 40,
        help:
            'Multiplies scene brightness like a small exposure adjustment. It affects shadows and highlights together.',
        format: (value) =>
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)} EV',
      ),
      AdjustmentControl(
        id: 'highlights',
        label: 'Highlights',
        value: (settings) => settings.highlights,
        apply: (settings, value) => settings.copyWith(highlights: value),
        min: -.6,
        max: .6,
        divisions: 48,
        help:
            'Brightens or darkens the lightest parts while protecting the rest of the tonal range.',
      ),
      AdjustmentControl(
        id: 'shadows',
        label: 'Shadows',
        value: (settings) => settings.shadows,
        apply: (settings, value) => settings.copyWith(shadows: value),
        min: -.6,
        max: .6,
        divisions: 48,
        help:
            'Opens or deepens darker areas without applying a full-image brightness change.',
      ),
      AdjustmentControl(
        id: 'black_point',
        label: 'Black point',
        value: (settings) => settings.blackPoint,
        apply: (settings, value) => settings.copyWith(blackPoint: value),
        min: 0,
        max: .5,
        divisions: 30,
        help:
            'Deepens the darkest tones. Increase carefully to avoid losing shadow detail.',
      ),
    ],
    EditorToolGroup.color => [
      AdjustmentControl(
        id: 'red_recovery',
        label: 'Red recovery',
        value: (settings) => settings.redRecovery,
        apply: (settings, value) => settings.copyWith(redRecovery: value),
        min: 0,
        max: 1.8,
        divisions: 36,
        help:
            'Targets warm colors absorbed by water. Its result is multiplied by Water correction, so both controls work together.',
      ),
      AdjustmentControl(
        id: 'auto_white_balance',
        label: 'Auto white balance',
        value: (settings) => settings.autoWhiteBalance,
        apply: (settings, value) => settings.copyWith(autoWhiteBalance: value),
        min: 0,
        max: 1,
        divisions: 20,
        help:
            'Balances the average red, green, and blue levels within safe bounds. Lower it when intentional lighting should stay warm or cool.',
      ),
      AdjustmentControl(
        id: 'saturation',
        label: 'Saturation',
        value: (settings) => settings.saturation,
        apply: (settings, value) => settings.copyWith(saturation: value),
        min: .6,
        max: 1.8,
        divisions: 48,
        help:
            'Changes the intensity of all colors equally. High values can exaggerate color noise and water tint.',
      ),
      AdjustmentControl(
        id: 'vibrance',
        label: 'Vibrance',
        value: (settings) => settings.vibrance,
        apply: (settings, value) => settings.copyWith(vibrance: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: 'Boosts muted colors more than colors that are already strong.',
      ),
      AdjustmentControl(
        id: 'hue',
        label: 'Hue',
        value: (settings) => settings.hue,
        apply: (settings, value) => settings.copyWith(hue: value),
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
        apply: (settings, value) =>
            settings.copyWith(highlightProtection: value),
        min: 0,
        max: 1,
        divisions: 20,
        help:
            'Reduces correction in the brightest areas to preserve strobes, the sun, and reflective equipment.',
      ),
    ],
    EditorToolGroup.details => [
      AdjustmentControl(
        id: 'haze_reduction',
        label: 'Haze reduction',
        value: (settings) => settings.hazeReduction,
        apply: (settings, value) => settings.copyWith(hazeReduction: value),
        min: 0,
        max: 1,
        divisions: 20,
        help:
            'Reduces blue-green veil and increases separation in low-contrast water.',
      ),
      AdjustmentControl(
        id: 'clarity',
        label: 'Clarity',
        value: (settings) => settings.clarity,
        apply: (settings, value) => settings.copyWith(clarity: value),
        min: 0,
        max: 1,
        divisions: 20,
        help:
            'Adds local midtone contrast to reveal texture. It is gentler than sharpening edges directly.',
      ),
      AdjustmentControl(
        id: 'sharpness',
        label: 'Sharpness',
        value: (settings) => settings.sharpness,
        apply: (settings, value) => settings.copyWith(sharpness: value),
        min: 0,
        max: 1,
        divisions: 20,
        help:
            'Strengthens fine edges during export. Too much can emphasize noise or compression artifacts.',
      ),
    ],
    EditorToolGroup.effects => [
      AdjustmentControl(
        id: 'vignette',
        label: 'Vignette',
        value: (settings) => settings.vignette,
        apply: (settings, value) => settings.copyWith(vignette: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: 'Darkens the image edges to guide attention toward the center.',
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

  bool get isOriginal => this == EditorCompareMode.original;

  bool get isSplit => this == EditorCompareMode.split;

  EditorCompareMode get toggled =>
      isSplit ? EditorCompareMode.edited : EditorCompareMode.split;
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
    EditorToolGroup.presets,
    EditorToolGroup.light,
    EditorToolGroup.effects,
    if (kind.isVideo) EditorToolGroup.video,
  ];
}

List<AdjustmentControl> get allImageAdjustmentControls => [
  ...EditorToolGroup.light.adjustments,
  ...EditorToolGroup.color.adjustments,
  ...EditorToolGroup.details.adjustments,
  ...EditorToolGroup.effects.adjustments,
];

const editorPresetChoices = [
  RestorationPreset.none,
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
