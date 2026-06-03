import 'dart:math' as math;

enum RestorationPreset {
  auto,
  natural,
  vivid,
  deep,
  macro,
  shallow,
  greenWater,
  redFilter,
  artificialLight,
  pro,
}

extension RestorationPresetX on RestorationPreset {
  String get label => switch (this) {
        RestorationPreset.auto => 'Auto',
        RestorationPreset.natural => 'Natural',
        RestorationPreset.vivid => 'Vivid reef',
        RestorationPreset.deep => 'Deep dive',
        RestorationPreset.macro => 'Macro',
        RestorationPreset.shallow => 'Shallow',
        RestorationPreset.greenWater => 'Green water',
        RestorationPreset.redFilter => 'Red filter',
        RestorationPreset.artificialLight => 'Artificial light',
        RestorationPreset.pro => 'Pro',
      };

  String get help => switch (this) {
        RestorationPreset.auto => 'Balanced one-tap correction for common blue-green water.',
        RestorationPreset.natural => 'Lower contrast and saturation for a documentary look.',
        RestorationPreset.vivid => 'Extra contrast and color for reef scenes.',
        RestorationPreset.deep => 'Stronger red recovery for deeper dives.',
        RestorationPreset.macro => 'More local detail for close subjects.',
        RestorationPreset.shallow => 'Gentle correction for snorkeling and sunlit shallow water.',
        RestorationPreset.greenWater => 'Counters green plankton-rich water without overdoing magenta.',
        RestorationPreset.redFilter => 'Compensates footage shot with a red dive filter.',
        RestorationPreset.artificialLight => 'Protects highlights from torches and strobes.',
        RestorationPreset.pro => 'Manual values.',
      };

  RestorationSettings get settings => switch (this) {
        RestorationPreset.auto => const RestorationSettings(),
        RestorationPreset.natural => const RestorationSettings(preset: RestorationPreset.natural, recovery: .82, redRecovery: 1.02, autoWhiteBalance: .78, contrastStretch: .46, contrast: 1.03, saturation: 1.08, vibrance: .12, clarity: .10, sharpness: .08, highlights: -.04, shadows: .05),
        RestorationPreset.vivid => const RestorationSettings(preset: RestorationPreset.vivid, recovery: 1.12, redRecovery: 1.26, autoWhiteBalance: .92, contrastStretch: .70, contrast: 1.16, gamma: .96, saturation: 1.38, vibrance: .28, clarity: .22, sharpness: .20, exposure: .03, blackPoint: .02),
        RestorationPreset.deep => const RestorationSettings(preset: RestorationPreset.deep, recovery: 1.35, redRecovery: 1.62, autoWhiteBalance: 1, contrastStretch: .74, contrast: 1.18, gamma: .94, saturation: 1.30, vibrance: .24, hazeReduction: .18, clarity: .18, sharpness: .16, shadows: .07, blackPoint: .03),
        RestorationPreset.macro => const RestorationSettings(preset: RestorationPreset.macro, recovery: .96, redRecovery: 1.18, autoWhiteBalance: .86, contrastStretch: .58, contrast: 1.12, saturation: 1.24, vibrance: .20, clarity: .34, sharpness: .30, highlightProtection: .70, highlights: -.09),
        RestorationPreset.shallow => const RestorationSettings(preset: RestorationPreset.shallow, recovery: .68, redRecovery: .92, autoWhiteBalance: .62, contrastStretch: .34, contrast: 1.02, saturation: 1.10, vibrance: .12, clarity: .08, sharpness: .08, exposure: .02),
        RestorationPreset.greenWater => const RestorationSettings(preset: RestorationPreset.greenWater, recovery: 1.10, redRecovery: 1.30, autoWhiteBalance: .98, contrastStretch: .68, contrast: 1.13, saturation: 1.18, vibrance: .22, hazeReduction: .28, hue: -.025, blackPoint: .035),
        RestorationPreset.redFilter => const RestorationSettings(preset: RestorationPreset.redFilter, recovery: .56, redRecovery: .72, autoWhiteBalance: .70, contrastStretch: .46, contrast: 1.06, gamma: 1.02, saturation: 1.08, vibrance: .10, highlights: -.06),
        RestorationPreset.artificialLight => const RestorationSettings(preset: RestorationPreset.artificialLight, recovery: .78, redRecovery: .96, autoWhiteBalance: .72, contrastStretch: .42, contrast: 1.08, saturation: 1.12, vibrance: .10, clarity: .18, sharpness: .18, highlightProtection: .86, highlights: -.18, shadows: .04),
        RestorationPreset.pro => const RestorationSettings(preset: RestorationPreset.pro),
      };
}

class RestorationSettings {
  const RestorationSettings({
    this.preset = RestorationPreset.auto,
    this.recovery = 1.0,
    this.redRecovery = 1.15,
    this.autoWhiteBalance = 0.9,
    this.contrastStretch = 0.58,
    this.contrast = 1.08,
    this.gamma = 0.98,
    this.saturation = 1.22,
    this.vibrance = 0.18,
    this.clarity = 0.18,
    this.sharpness = 0.18,
    this.hazeReduction = 0.10,
    this.highlightProtection = 0.55,
    this.hue = 0,
    this.brightness = 0,
    this.exposure = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.blackPoint = 0,
    this.vignette = 0,
    this.jpegQuality = 94,
  });

  final RestorationPreset preset;
  final double recovery;
  final double redRecovery;
  final double autoWhiteBalance;
  final double contrastStretch;
  final double contrast;
  final double gamma;
  final double saturation;
  final double vibrance;
  final double clarity;
  final double sharpness;
  final double hazeReduction;
  final double highlightProtection;
  final double hue;
  final double brightness;
  final double exposure;
  final double highlights;
  final double shadows;
  final double blackPoint;
  final double vignette;
  final int jpegQuality;

  RestorationSettings copyWith({
    RestorationPreset? preset,
    double? recovery,
    double? redRecovery,
    double? autoWhiteBalance,
    double? contrastStretch,
    double? contrast,
    double? gamma,
    double? saturation,
    double? vibrance,
    double? clarity,
    double? sharpness,
    double? hazeReduction,
    double? highlightProtection,
    double? hue,
    double? brightness,
    double? exposure,
    double? highlights,
    double? shadows,
    double? blackPoint,
    double? vignette,
    int? jpegQuality,
  }) {
    return RestorationSettings(
      preset: preset ?? this.preset,
      recovery: recovery ?? this.recovery,
      redRecovery: redRecovery ?? this.redRecovery,
      autoWhiteBalance: autoWhiteBalance ?? this.autoWhiteBalance,
      contrastStretch: contrastStretch ?? this.contrastStretch,
      contrast: contrast ?? this.contrast,
      gamma: gamma ?? this.gamma,
      saturation: saturation ?? this.saturation,
      vibrance: vibrance ?? this.vibrance,
      clarity: clarity ?? this.clarity,
      sharpness: sharpness ?? this.sharpness,
      hazeReduction: hazeReduction ?? this.hazeReduction,
      highlightProtection: highlightProtection ?? this.highlightProtection,
      hue: hue ?? this.hue,
      brightness: brightness ?? this.brightness,
      exposure: exposure ?? this.exposure,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      blackPoint: blackPoint ?? this.blackPoint,
      vignette: vignette ?? this.vignette,
      jpegQuality: jpegQuality ?? this.jpegQuality,
    );
  }

  RestorationSettings asPro({
    double? recovery,
    double? redRecovery,
    double? autoWhiteBalance,
    double? contrastStretch,
    double? contrast,
    double? gamma,
    double? saturation,
    double? vibrance,
    double? clarity,
    double? sharpness,
    double? hazeReduction,
    double? highlightProtection,
    double? hue,
    double? brightness,
    double? exposure,
    double? highlights,
    double? shadows,
    double? blackPoint,
    double? vignette,
    int? jpegQuality,
  }) {
    return copyWith(
      preset: RestorationPreset.pro,
      recovery: recovery,
      redRecovery: redRecovery,
      autoWhiteBalance: autoWhiteBalance,
      contrastStretch: contrastStretch,
      contrast: contrast,
      gamma: gamma,
      saturation: saturation,
      vibrance: vibrance,
      clarity: clarity,
      sharpness: sharpness,
      hazeReduction: hazeReduction,
      highlightProtection: highlightProtection,
      hue: hue,
      brightness: brightness,
      exposure: exposure,
      highlights: highlights,
      shadows: shadows,
      blackPoint: blackPoint,
      vignette: vignette,
      jpegQuality: jpegQuality,
    );
  }

  List<String> ffmpegFilters({List<String> extraFilters = const []}) {
    final safeRecovery = recovery.clamp(0.0, 1.5).toDouble();
    final red = (0.18 * safeRecovery * redRecovery).clamp(-1.0, 1.0).toDouble();
    final blueTrim = (-0.045 * safeRecovery).clamp(-1.0, 1.0).toDouble();
    final greenTrim = (-0.020 * hazeReduction).clamp(-0.25, 0.0).toDouble();
    final sat = math.max(0.1, saturation + vibrance * 0.22);
    final ctr = math.max(0.1, contrast + hazeReduction * 0.08);
    final bright = (0.012 + brightness * 0.32 + exposure * 0.22 + shadows * 0.06 + highlights * 0.04 - blackPoint * 0.10).clamp(-1.0, 1.0).toDouble();
    final sharp = ((sharpness + clarity * 0.65) * 0.85).clamp(0.0, 2.0).toDouble();
    final hueDegrees = (hue.clamp(-1.0, 1.0) * 180.0).toDouble();
    return [
      'colorbalance=rs=${red.toStringAsFixed(4)}:rm=${red.toStringAsFixed(4)}:rh=${red.toStringAsFixed(4)}:gs=${greenTrim.toStringAsFixed(4)}:gm=${greenTrim.toStringAsFixed(4)}:gh=${greenTrim.toStringAsFixed(4)}:bs=${blueTrim.toStringAsFixed(4)}:bm=${blueTrim.toStringAsFixed(4)}:bh=${blueTrim.toStringAsFixed(4)}',
      'eq=contrast=${ctr.toStringAsFixed(3)}:saturation=${sat.toStringAsFixed(3)}:gamma=${gamma.clamp(0.1, 3.0).toStringAsFixed(3)}:brightness=${bright.toStringAsFixed(3)}',
      if (hueDegrees.abs() > .001) 'hue=h=${hueDegrees.toStringAsFixed(2)}',
      if (sharp > 0.001) 'unsharp=5:5:${sharp.toStringAsFixed(3)}:3:3:0.0',
      if (vignette > 0.001) 'vignette=PI/5',
      ...extraFilters,
      'format=yuv420p',
    ];
  }

  String get ffmpegFilter => ffmpegFilters().join(',');

  Map<String, Object> toJson() => {
        'preset': preset.name,
        'recovery': recovery,
        'redRecovery': redRecovery,
        'autoWhiteBalance': autoWhiteBalance,
        'contrastStretch': contrastStretch,
        'contrast': contrast,
        'gamma': gamma,
        'saturation': saturation,
        'vibrance': vibrance,
        'clarity': clarity,
        'sharpness': sharpness,
        'hazeReduction': hazeReduction,
        'highlightProtection': highlightProtection,
        'hue': hue,
        'brightness': brightness,
        'exposure': exposure,
        'highlights': highlights,
        'shadows': shadows,
        'blackPoint': blackPoint,
        'vignette': vignette,
        'jpegQuality': jpegQuality,
      };
}
