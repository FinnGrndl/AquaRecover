import 'dart:math' as math;

enum RestorationPreset {
  none,
  auto,
  natural,
  vivid,
  deep,
  macro,
  shallow,
  greenWater,
  redFilter,
  artificialLight,
}

extension RestorationPresetX on RestorationPreset {
  String get label => switch (this) {
    RestorationPreset.none => 'None',
    RestorationPreset.auto => 'Auto',
    RestorationPreset.natural => 'Natural',
    RestorationPreset.vivid => 'Vivid reef',
    RestorationPreset.deep => 'Deep dive',
    RestorationPreset.macro => 'Macro',
    RestorationPreset.shallow => 'Shallow',
    RestorationPreset.greenWater => 'Green water',
    RestorationPreset.redFilter => 'Red filter',
    RestorationPreset.artificialLight => 'Artificial light',
  };

  String get help => switch (this) {
    RestorationPreset.none => 'Leaves the image unchanged.',
    RestorationPreset.auto =>
      'Balanced one-tap correction for common blue-green water.',
    RestorationPreset.natural =>
      'Lower contrast and saturation for a documentary look.',
    RestorationPreset.vivid => 'Extra contrast and color for reef scenes.',
    RestorationPreset.deep => 'Stronger red recovery for deeper dives.',
    RestorationPreset.macro => 'More local detail for close subjects.',
    RestorationPreset.shallow =>
      'Gentle correction for snorkeling and sunlit shallow water.',
    RestorationPreset.greenWater =>
      'Counters green plankton-rich water without overdoing magenta.',
    RestorationPreset.redFilter =>
      'Compensates footage shot with a red dive filter.',
    RestorationPreset.artificialLight =>
      'Protects highlights from torches and strobes.',
  };

  RestorationSettings get settings => switch (this) {
    RestorationPreset.none => const RestorationSettings(
      preset: RestorationPreset.none,
      presetStrength: 0,
      recovery: 0,
      redRecovery: 0,
      autoWhiteBalance: 0,
      contrastStretch: 0,
      contrast: 1,
      gamma: 1,
      saturation: 1,
      vibrance: 0,
      clarity: 0,
      sharpness: 0,
      hazeReduction: 0,
      highlightProtection: 0,
      hue: 0,
      brightness: 0,
      exposure: 0,
      highlights: 0,
      shadows: 0,
      blackPoint: 0,
      vignette: 0,
    ),
    RestorationPreset.auto => const RestorationSettings(),
    RestorationPreset.natural => const RestorationSettings(
      preset: RestorationPreset.natural,
      recovery: .82,
      redRecovery: 1.02,
      autoWhiteBalance: .78,
      contrastStretch: .46,
      contrast: 1.03,
      saturation: 1.08,
      vibrance: .12,
      clarity: .10,
      sharpness: .08,
      highlights: -.04,
      shadows: .05,
    ),
    RestorationPreset.vivid => const RestorationSettings(
      preset: RestorationPreset.vivid,
      recovery: 1.12,
      redRecovery: 1.26,
      autoWhiteBalance: .92,
      contrastStretch: .70,
      contrast: 1.16,
      gamma: .96,
      saturation: 1.38,
      vibrance: .28,
      clarity: .22,
      sharpness: .20,
      exposure: .03,
      blackPoint: .02,
    ),
    RestorationPreset.deep => const RestorationSettings(
      preset: RestorationPreset.deep,
      recovery: 1.35,
      redRecovery: 1.62,
      autoWhiteBalance: 1,
      contrastStretch: .74,
      contrast: 1.18,
      gamma: .94,
      saturation: 1.30,
      vibrance: .24,
      hazeReduction: .18,
      clarity: .18,
      sharpness: .16,
      shadows: .07,
      blackPoint: .03,
    ),
    RestorationPreset.macro => const RestorationSettings(
      preset: RestorationPreset.macro,
      recovery: .96,
      redRecovery: 1.18,
      autoWhiteBalance: .86,
      contrastStretch: .58,
      contrast: 1.12,
      saturation: 1.24,
      vibrance: .20,
      clarity: .34,
      sharpness: .30,
      highlightProtection: .70,
      highlights: -.09,
    ),
    RestorationPreset.shallow => const RestorationSettings(
      preset: RestorationPreset.shallow,
      recovery: .68,
      redRecovery: .92,
      autoWhiteBalance: .62,
      contrastStretch: .34,
      contrast: 1.02,
      saturation: 1.10,
      vibrance: .12,
      clarity: .08,
      sharpness: .08,
      exposure: .02,
    ),
    RestorationPreset.greenWater => const RestorationSettings(
      preset: RestorationPreset.greenWater,
      recovery: 1.10,
      redRecovery: 1.30,
      autoWhiteBalance: .98,
      contrastStretch: .68,
      contrast: 1.13,
      saturation: 1.18,
      vibrance: .22,
      hazeReduction: .28,
      hue: -.025,
      blackPoint: .035,
    ),
    RestorationPreset.redFilter => const RestorationSettings(
      preset: RestorationPreset.redFilter,
      recovery: .56,
      redRecovery: .72,
      autoWhiteBalance: .70,
      contrastStretch: .46,
      contrast: 1.06,
      gamma: 1.02,
      saturation: 1.08,
      vibrance: .10,
      highlights: -.06,
    ),
    RestorationPreset.artificialLight => const RestorationSettings(
      preset: RestorationPreset.artificialLight,
      recovery: .78,
      redRecovery: .96,
      autoWhiteBalance: .72,
      contrastStretch: .42,
      contrast: 1.08,
      saturation: 1.12,
      vibrance: .10,
      clarity: .18,
      sharpness: .18,
      highlightProtection: .86,
      highlights: -.18,
      shadows: .04,
    ),
  };

  RestorationSettings settingsAtStrength(double strength) {
    if (this == RestorationPreset.none) return settings;
    final amount = strength.clamp(0.0, 1.0).toDouble();
    final neutral = RestorationPreset.none.settings;
    final target = settings;
    return RestorationSettings(
      preset: this,
      presetStrength: amount,
      recovery: _mix(neutral.recovery, target.recovery, amount),
      redRecovery: _mix(neutral.redRecovery, target.redRecovery, amount),
      autoWhiteBalance: _mix(
        neutral.autoWhiteBalance,
        target.autoWhiteBalance,
        amount,
      ),
      contrastStretch: _mix(
        neutral.contrastStretch,
        target.contrastStretch,
        amount,
      ),
      contrast: _mix(neutral.contrast, target.contrast, amount),
      gamma: _mix(neutral.gamma, target.gamma, amount),
      saturation: _mix(neutral.saturation, target.saturation, amount),
      vibrance: _mix(neutral.vibrance, target.vibrance, amount),
      clarity: _mix(neutral.clarity, target.clarity, amount),
      sharpness: _mix(neutral.sharpness, target.sharpness, amount),
      hazeReduction: _mix(neutral.hazeReduction, target.hazeReduction, amount),
      highlightProtection: _mix(
        neutral.highlightProtection,
        target.highlightProtection,
        amount,
      ),
      hue: _mix(neutral.hue, target.hue, amount),
      brightness: _mix(neutral.brightness, target.brightness, amount),
      exposure: _mix(neutral.exposure, target.exposure, amount),
      highlights: _mix(neutral.highlights, target.highlights, amount),
      shadows: _mix(neutral.shadows, target.shadows, amount),
      blackPoint: _mix(neutral.blackPoint, target.blackPoint, amount),
      vignette: _mix(neutral.vignette, target.vignette, amount),
      jpegQuality: target.jpegQuality,
    );
  }

  static double _mix(double start, double end, double amount) {
    return start + (end - start) * amount;
  }
}

class RestorationSettings {
  const RestorationSettings({
    this.preset = RestorationPreset.auto,
    this.presetStrength = 1,
    this.recovery = 1.18,
    this.redRecovery = 1.24,
    this.autoWhiteBalance = 0.76,
    this.contrastStretch = 0.52,
    this.contrast = 1.04,
    this.gamma = 0.98,
    this.saturation = 0.88,
    this.vibrance = 0.06,
    this.clarity = 0.18,
    this.sharpness = 0.18,
    this.hazeReduction = 0.14,
    this.highlightProtection = 0.55,
    this.hue = 0,
    this.brightness = 0,
    this.exposure = -0.04,
    this.highlights = 0,
    this.shadows = 0,
    this.blackPoint = 0,
    this.vignette = 0,
    this.jpegQuality = 94,
  });

  final RestorationPreset preset;
  final double presetStrength;
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
    double? presetStrength,
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
      presetStrength: presetStrength ?? this.presetStrength,
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

  RestorationSettings get presetBaseline => preset.settingsAtStrength(
    preset == RestorationPreset.none ? 0 : presetStrength,
  );

  RestorationSettings withPresetStrength(double strength) {
    if (preset == RestorationPreset.none) return this;
    final amount = strength.clamp(0.0, 1.0).toDouble();
    final oldBase = presetBaseline;
    final newBase = preset.settingsAtStrength(amount);
    return copyWith(
      presetStrength: amount,
      recovery: newBase.recovery + recovery - oldBase.recovery,
      redRecovery: newBase.redRecovery + redRecovery - oldBase.redRecovery,
      autoWhiteBalance:
          newBase.autoWhiteBalance +
          autoWhiteBalance -
          oldBase.autoWhiteBalance,
      contrastStretch:
          newBase.contrastStretch + contrastStretch - oldBase.contrastStretch,
      contrast: newBase.contrast + contrast - oldBase.contrast,
      gamma: newBase.gamma + gamma - oldBase.gamma,
      saturation: newBase.saturation + saturation - oldBase.saturation,
      vibrance: newBase.vibrance + vibrance - oldBase.vibrance,
      clarity: newBase.clarity + clarity - oldBase.clarity,
      sharpness: newBase.sharpness + sharpness - oldBase.sharpness,
      hazeReduction:
          newBase.hazeReduction + hazeReduction - oldBase.hazeReduction,
      highlightProtection:
          newBase.highlightProtection +
          highlightProtection -
          oldBase.highlightProtection,
      hue: newBase.hue + hue - oldBase.hue,
      brightness: newBase.brightness + brightness - oldBase.brightness,
      exposure: newBase.exposure + exposure - oldBase.exposure,
      highlights: newBase.highlights + highlights - oldBase.highlights,
      shadows: newBase.shadows + shadows - oldBase.shadows,
      blackPoint: newBase.blackPoint + blackPoint - oldBase.blackPoint,
      vignette: newBase.vignette + vignette - oldBase.vignette,
    );
  }

  bool get isIdentity {
    final neutral = RestorationPreset.none.settings;
    bool same(double a, double b) => (a - b).abs() < 0.0000001;
    return same(recovery, neutral.recovery) &&
        same(redRecovery, neutral.redRecovery) &&
        same(autoWhiteBalance, neutral.autoWhiteBalance) &&
        same(contrastStretch, neutral.contrastStretch) &&
        same(contrast, neutral.contrast) &&
        same(gamma, neutral.gamma) &&
        same(saturation, neutral.saturation) &&
        same(vibrance, neutral.vibrance) &&
        same(clarity, neutral.clarity) &&
        same(sharpness, neutral.sharpness) &&
        same(hazeReduction, neutral.hazeReduction) &&
        same(highlightProtection, neutral.highlightProtection) &&
        same(hue, neutral.hue) &&
        same(brightness, neutral.brightness) &&
        same(exposure, neutral.exposure) &&
        same(highlights, neutral.highlights) &&
        same(shadows, neutral.shadows) &&
        same(blackPoint, neutral.blackPoint) &&
        same(vignette, neutral.vignette);
  }

  List<String> ffmpegFilters({List<String> extraFilters = const []}) {
    if (isIdentity) return [...extraFilters, 'format=yuv420p'];
    final safeRecovery = recovery.clamp(0.0, 1.5).toDouble();
    final red = (0.040 * safeRecovery * redRecovery)
        .clamp(-0.18, 0.18)
        .toDouble();
    final blueTrim = (-0.018 * safeRecovery).clamp(-0.12, 0.0).toDouble();
    final greenTrim = (-0.014 * hazeReduction).clamp(-0.14, 0.0).toDouble();
    final sat = math.max(
      0.1,
      1.0 + (saturation - 1.0) * 0.65 + vibrance * 0.10,
    );
    final ctr = math.max(
      0.1,
      1.0 + (contrast - 1.0) * 0.85 + hazeReduction * 0.05,
    );
    final bright =
        (0.006 +
                brightness * 0.24 +
                exposure * 0.18 +
                shadows * 0.045 +
                highlights * 0.03 -
                blackPoint * 0.08)
            .clamp(-1.0, 1.0)
            .toDouble();
    final sharp = ((sharpness + clarity * 0.65) * 0.70)
        .clamp(0.0, 1.5)
        .toDouble();
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
    'presetStrength': presetStrength,
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
