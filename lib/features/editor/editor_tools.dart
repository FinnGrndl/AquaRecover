import '../../core/models/media_kind.dart';
import '../../core/models/restoration_settings.dart';
import '../../l10n/l10n.dart';

typedef SettingValueReader = double Function(RestorationSettings settings);
typedef SettingValueWriter =
    RestorationSettings Function(RestorationSettings settings, double value);

/// Text that follows the app language.
typedef LocalizedText = String Function(AppLocalizations l10n);

enum EditorToolGroup { presets, light, crop, color, details, effects, video }

extension EditorToolGroupX on EditorToolGroup {
  String labelIn(AppLocalizations l10n) => switch (this) {
    EditorToolGroup.presets => l10n.toolPresets,
    EditorToolGroup.light => l10n.toolAdjust,
    EditorToolGroup.crop => l10n.toolCrop,
    EditorToolGroup.color => l10n.toolColor,
    EditorToolGroup.details => l10n.toolDetails,
    EditorToolGroup.effects => l10n.toolLut,
    EditorToolGroup.video => l10n.toolVideo,
  };

  String subtitleIn(AppLocalizations l10n) => switch (this) {
    EditorToolGroup.presets => l10n.toolPresetsSubtitle,
    EditorToolGroup.light => l10n.toolAdjustSubtitle,
    EditorToolGroup.crop => l10n.toolCropSubtitle,
    EditorToolGroup.color => l10n.toolColorSubtitle,
    EditorToolGroup.details => l10n.toolDetailsSubtitle,
    EditorToolGroup.effects => l10n.toolLutSubtitle,
    EditorToolGroup.video => l10n.toolVideoSubtitle,
  };

  bool isAvailableFor(MediaKind kind) {
    return switch (this) {
      EditorToolGroup.video => kind.isVideo,
      EditorToolGroup.crop => kind == MediaKind.photo,
      _ => true,
    };
  }

  List<AdjustmentControl> get adjustments => switch (this) {
    EditorToolGroup.light => [
      AdjustmentControl(
        id: 'recovery',
        label: (l10n) => l10n.adjRecovery,
        value: (settings) => settings.recovery,
        apply: (settings, value) => settings.copyWith(recovery: value),
        min: 0,
        max: 1.5,
        divisions: 30,
        help: (l10n) => l10n.adjRecoveryHelp,
        format: (value) => '${(value * 100).round()}%',
      ),
      AdjustmentControl(
        id: 'contrast_stretch',
        label: (l10n) => l10n.adjContrastStretch,
        value: (settings) => settings.contrastStretch,
        apply: (settings, value) => settings.copyWith(contrastStretch: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: (l10n) => l10n.adjContrastStretchHelp,
      ),
      AdjustmentControl(
        id: 'contrast',
        label: (l10n) => l10n.adjContrast,
        value: (settings) => settings.contrast,
        apply: (settings, value) => settings.copyWith(contrast: value),
        min: .7,
        max: 1.6,
        divisions: 45,
        help: (l10n) => l10n.adjContrastHelp,
      ),
      AdjustmentControl(
        id: 'gamma',
        label: (l10n) => l10n.adjGamma,
        value: (settings) => settings.gamma,
        apply: (settings, value) => settings.copyWith(gamma: value),
        min: .75,
        max: 1.35,
        divisions: 30,
        help: (l10n) => l10n.adjGammaHelp,
      ),
      AdjustmentControl(
        id: 'brightness',
        label: (l10n) => l10n.adjBrightness,
        value: (settings) => settings.brightness,
        apply: (settings, value) => settings.copyWith(brightness: value),
        min: -.5,
        max: .5,
        divisions: 40,
        help: (l10n) => l10n.adjBrightnessHelp,
      ),
      AdjustmentControl(
        id: 'exposure',
        label: (l10n) => l10n.adjExposure,
        value: (settings) => settings.exposure,
        apply: (settings, value) => settings.copyWith(exposure: value),
        min: -.5,
        max: .5,
        divisions: 40,
        help: (l10n) => l10n.adjExposureHelp,
        format: (value) =>
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)} EV',
      ),
      AdjustmentControl(
        id: 'highlights',
        label: (l10n) => l10n.adjHighlights,
        value: (settings) => settings.highlights,
        apply: (settings, value) => settings.copyWith(highlights: value),
        min: -.6,
        max: .6,
        divisions: 48,
        help: (l10n) => l10n.adjHighlightsHelp,
      ),
      AdjustmentControl(
        id: 'shadows',
        label: (l10n) => l10n.adjShadows,
        value: (settings) => settings.shadows,
        apply: (settings, value) => settings.copyWith(shadows: value),
        min: -.6,
        max: .6,
        divisions: 48,
        help: (l10n) => l10n.adjShadowsHelp,
      ),
      AdjustmentControl(
        id: 'black_point',
        label: (l10n) => l10n.adjBlackPoint,
        value: (settings) => settings.blackPoint,
        apply: (settings, value) => settings.copyWith(blackPoint: value),
        min: 0,
        max: .5,
        divisions: 30,
        help: (l10n) => l10n.adjBlackPointHelp,
      ),
    ],
    EditorToolGroup.color => [
      AdjustmentControl(
        id: 'temperature',
        label: (l10n) => l10n.adjTemperature,
        value: (settings) => settings.temperature,
        apply: (settings, value) => settings.copyWith(temperature: value),
        min: -1,
        max: 1,
        divisions: 40,
        help: (l10n) => l10n.adjTemperatureHelp,
        format: _signedPercent,
      ),
      AdjustmentControl(
        id: 'tint',
        label: (l10n) => l10n.adjTint,
        value: (settings) => settings.tint,
        apply: (settings, value) => settings.copyWith(tint: value),
        min: -1,
        max: 1,
        divisions: 40,
        help: (l10n) => l10n.adjTintHelp,
        format: _signedPercent,
      ),
      AdjustmentControl(
        id: 'red_recovery',
        label: (l10n) => l10n.adjRedRecovery,
        value: (settings) => settings.redRecovery,
        apply: (settings, value) => settings.copyWith(redRecovery: value),
        min: 0,
        max: 1.8,
        divisions: 36,
        help: (l10n) => l10n.adjRedRecoveryHelp,
      ),
      AdjustmentControl(
        id: 'auto_white_balance',
        label: (l10n) => l10n.adjAutoWhiteBalance,
        value: (settings) => settings.autoWhiteBalance,
        apply: (settings, value) => settings.copyWith(autoWhiteBalance: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: (l10n) => l10n.adjAutoWhiteBalanceHelp,
      ),
      AdjustmentControl(
        id: 'saturation',
        label: (l10n) => l10n.adjSaturation,
        value: (settings) => settings.saturation,
        apply: (settings, value) => settings.copyWith(saturation: value),
        min: .6,
        max: 1.8,
        divisions: 48,
        help: (l10n) => l10n.adjSaturationHelp,
      ),
      AdjustmentControl(
        id: 'vibrance',
        label: (l10n) => l10n.adjVibrance,
        value: (settings) => settings.vibrance,
        apply: (settings, value) => settings.copyWith(vibrance: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: (l10n) => l10n.adjVibranceHelp,
      ),
      AdjustmentControl(
        id: 'hue',
        label: (l10n) => l10n.adjHue,
        value: (settings) => settings.hue,
        apply: (settings, value) => settings.copyWith(hue: value),
        min: -.25,
        max: .25,
        divisions: 50,
        help: (l10n) => l10n.adjHueHelp,
      ),
      AdjustmentControl(
        id: 'highlight_protection',
        label: (l10n) => l10n.adjHighlightProtection,
        value: (settings) => settings.highlightProtection,
        apply: (settings, value) =>
            settings.copyWith(highlightProtection: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: (l10n) => l10n.adjHighlightProtectionHelp,
      ),
    ],
    EditorToolGroup.details => [
      AdjustmentControl(
        id: 'haze_reduction',
        label: (l10n) => l10n.adjHazeReduction,
        value: (settings) => settings.hazeReduction,
        apply: (settings, value) => settings.copyWith(hazeReduction: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: (l10n) => l10n.adjHazeReductionHelp,
      ),
      AdjustmentControl(
        id: 'clarity',
        label: (l10n) => l10n.adjClarity,
        value: (settings) => settings.clarity,
        apply: (settings, value) => settings.copyWith(clarity: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: (l10n) => l10n.adjClarityHelp,
      ),
      AdjustmentControl(
        id: 'sharpness',
        label: (l10n) => l10n.adjSharpness,
        value: (settings) => settings.sharpness,
        apply: (settings, value) => settings.copyWith(sharpness: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: (l10n) => l10n.adjSharpnessHelp,
      ),
    ],
    EditorToolGroup.effects => [
      AdjustmentControl(
        id: 'vignette',
        label: (l10n) => l10n.adjVignette,
        value: (settings) => settings.vignette,
        apply: (settings, value) => settings.copyWith(vignette: value),
        min: 0,
        max: 1,
        divisions: 20,
        help: (l10n) => l10n.adjVignetteHelp,
      ),
    ],
    _ => const [],
  };
}

enum EditorCompareMode { edited, original, split }

extension EditorCompareModeX on EditorCompareMode {
  String labelIn(AppLocalizations l10n) => switch (this) {
    EditorCompareMode.edited => l10n.compareEdited,
    EditorCompareMode.original => l10n.compareOriginal,
    EditorCompareMode.split => l10n.compareSplit,
  };

  bool get isOriginal => this == EditorCompareMode.original;

  bool get isSplit => this == EditorCompareMode.split;

  EditorCompareMode get toggled =>
      isSplit ? EditorCompareMode.edited : EditorCompareMode.split;
}

enum EditorPreviewFit { fit, fill }

extension EditorPreviewFitX on EditorPreviewFit {
  String labelIn(AppLocalizations l10n) => this == EditorPreviewFit.fit
      ? l10n.previewFitLabel
      : l10n.previewFillLabel;

  String actionLabelIn(AppLocalizations l10n) => this == EditorPreviewFit.fit
      ? l10n.previewFillAction
      : l10n.previewFitAction;

  EditorPreviewFit get toggled => this == EditorPreviewFit.fit
      ? EditorPreviewFit.fill
      : EditorPreviewFit.fit;
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
  final LocalizedText label;
  final SettingValueReader value;
  final SettingValueWriter apply;
  final double min;
  final double max;
  final int? divisions;
  final LocalizedText? help;
  final String Function(double value)? format;
}

List<EditorToolGroup> activeEditorToolGroupsFor(MediaKind kind) {
  return [
    EditorToolGroup.presets,
    EditorToolGroup.light,
    if (kind == MediaKind.photo) EditorToolGroup.crop,
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

String _signedPercent(double value) {
  final percent = (value * 100).round();
  return percent > 0 ? '+$percent' : (percent < 0 ? '\u2212${-percent}' : '0');
}
