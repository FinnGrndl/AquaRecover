import 'timeline_json.dart';

/// Where an effect is listed in the effect picker.
enum EffectCategory {
  look('Look'),
  lens('Lens'),
  underwater('Underwater'),
  motion('Motion');

  const EffectCategory(this.label);

  final String label;
}

/// How the compiler realises an effect, which decides what every renderer has
/// to do for it.
enum EffectKind {
  /// Folded into the clip's single 4×5 colour matrix.
  colorMatrix,

  /// A per-pixel filter on the clip's pixels: blur, sharpen, or grain.
  filter,

  /// A texture or colour layer composited over the canvas.
  layer,

  /// Transform keys on the main clip.
  motion,
}

/// The built-in effect catalogue. [id] is the stable JSON name; never rename
/// it, because saved projects and native renderers refer to it.
enum EffectType {
  mono(
    'mono',
    'Mono',
    EffectCategory.look,
    EffectKind.colorMatrix,
    1.0,
    overlayAllowed: true,
  ),
  sepia(
    'sepia',
    'Sepia',
    EffectCategory.look,
    EffectKind.colorMatrix,
    0.8,
    overlayAllowed: true,
  ),
  cyanotype(
    'cyanotype',
    'Cyanotype',
    EffectCategory.look,
    EffectKind.colorMatrix,
    0.8,
    overlayAllowed: true,
  ),
  deepBlue(
    'deepBlue',
    'Deep Blue',
    EffectCategory.underwater,
    EffectKind.colorMatrix,
    0.5,
    overlayAllowed: true,
  ),
  vivid(
    'vivid',
    'Vivid',
    EffectCategory.look,
    EffectKind.colorMatrix,
    0.5,
    overlayAllowed: true,
  ),
  faded(
    'faded',
    'Faded Film',
    EffectCategory.look,
    EffectKind.colorMatrix,
    0.5,
    overlayAllowed: true,
  ),
  softFocus(
    'softFocus',
    'Soft Focus',
    EffectCategory.lens,
    EffectKind.filter,
    0.4,
    overlayAllowed: true,
  ),
  clarity(
    'clarity',
    'Clarity',
    EffectCategory.lens,
    EffectKind.filter,
    0.4,
    overlayAllowed: true,
  ),
  grain(
    'grain',
    'Film Grain',
    EffectCategory.lens,
    EffectKind.filter,
    0.3,
    animated: true,
    overlayAllowed: true,
  ),
  vignette('vignette', 'Vignette', EffectCategory.lens, EffectKind.layer, 0.5),
  cinemaBars(
    'cinemaBars',
    'Cinema Bars',
    EffectCategory.lens,
    EffectKind.layer,
    1.0,
  ),
  sunRays(
    'sunRays',
    'Sun Rays',
    EffectCategory.underwater,
    EffectKind.layer,
    0.4,
    animated: true,
  ),
  caustics(
    'caustics',
    'Caustics',
    EffectCategory.underwater,
    EffectKind.layer,
    0.35,
    animated: true,
  ),
  strobe(
    'strobe',
    'Strobe Flash',
    EffectCategory.underwater,
    EffectKind.layer,
    0.7,
    animated: true,
  ),
  swell(
    'swell',
    'Swell',
    EffectCategory.motion,
    EffectKind.motion,
    0.4,
    animated: true,
  ),
  drift(
    'drift',
    'Slow Drift',
    EffectCategory.motion,
    EffectKind.motion,
    0.5,
    animated: true,
  );

  const EffectType(
    this.id,
    this.label,
    this.category,
    this.kind,
    this.defaultIntensity, {
    this.animated = false,
    this.overlayAllowed = false,
  });

  /// Stable JSON name.
  final String id;

  /// English UI label.
  final String label;
  final EffectCategory category;
  final EffectKind kind;

  /// Intensity a newly added effect starts at, 0 to 1.
  final double defaultIntensity;

  /// Whether the effect changes over time.
  final bool animated;

  /// Whether the effect can be used on overlay items, not only main clips.
  final bool overlayAllowed;

  /// Effects rendered from a generated texture (see `rasterizeEffectTexture`).
  bool get usesTexture => switch (this) {
    vignette || cinemaBars || sunRays || caustics => true,
    _ => false,
  };

  /// The effect called [id], or `null` for ids this version does not know.
  static EffectType? byId(Object? id) {
    for (final type in values) {
      if (type.id == id) return type;
    }
    return null;
  }

  /// Effects listed under [category], in catalogue order.
  static List<EffectType> inCategory(EffectCategory category) => [
    for (final type in values)
      if (type.category == category) type,
  ];
}

/// One effect on a clip or overlay with its strength.
class ClipEffect {
  /// [intensity] defaults to the catalogue's [EffectType.defaultIntensity] and
  /// is clamped to 0…1.
  ClipEffect(this.type, {double? intensity})
    : intensity = (intensity ?? type.defaultIntensity).clamp(0.0, 1.0);

  final EffectType type;

  /// Strength from 0 (no effect) to 1 (full effect).
  final double intensity;

  ClipEffect copyWith({double? intensity}) =>
      ClipEffect(type, intensity: intensity ?? this.intensity);

  Map<String, Object?> toJson() => {'type': type.id, 'intensity': intensity};

  /// Throws a [FormatException] for an effect id this version does not know;
  /// [listFromJson] skips those instead.
  factory ClipEffect.fromJson(Map<String, Object?> json) {
    final type = EffectType.byId(json['type']);
    if (type == null) {
      throw FormatException('Unknown effect "${json['type']}".');
    }
    return ClipEffect(type, intensity: jsonOptionalDouble(json, 'intensity'));
  }

  /// The effects stored under `json[key]`, skipping unknown ones.
  static List<ClipEffect> listFromJson(Map<String, Object?> json, String key) =>
      List.unmodifiable([
        for (final item in jsonMaps(json, key))
          if (EffectType.byId(item['type']) != null) ClipEffect.fromJson(item),
      ]);

  @override
  bool operator ==(Object other) =>
      other is ClipEffect && other.type == type && other.intensity == intensity;

  @override
  int get hashCode => Object.hash(type, intensity);

  @override
  String toString() => 'ClipEffect(${type.id}, $intensity)';
}

/// 4×5 row-major colour matrices on gamma-encoded RGBA in 0…1:
/// `[r0..r4, g0..g4, b0..b4, a0..a4]`, where column 4 is an offset in 0…1
/// units (not 0…255 as Flutter's `ColorFilter.matrix` expects; see
/// [withByteOffsets]).
abstract final class ColorMatrices {
  static const identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  /// Rec.709 luma weights.
  static const luma = <double>[0.2126, 0.7152, 0.0722];

  /// The full-strength matrix of a [EffectKind.colorMatrix] effect.
  static List<double> full(EffectType type) => switch (type) {
    EffectType.mono => _tintedLuma(const [1, 1, 1]),
    EffectType.sepia => _tintedLuma(const [1.07, 0.74, 0.43]),
    EffectType.cyanotype => _tintedLuma(
      const [0.35, 0.75, 1.0],
      offsets: const [0, 0.02, 0.06],
    ),
    // Red cut, a touch of blue into green, blue boost, and a 0.03 black lift
    // on green and blue.
    EffectType.deepBlue => const [
      0.78, 0, 0, 0, 0, //
      0, 0.96, 0.02, 0, 0.03, //
      0, 0, 1.04, 0, 0.05, //
      0, 0, 0, 1, 0, //
    ],
    EffectType.vivid => saturation(1.35),
    // Saturation 0.85, then contrast 0.82 around 0.5 (offset 0.09), then a
    // 0.06 lift: x' = 0.82·S(x) + 0.15.
    EffectType.faded => _scaled(saturation(0.85), 0.82, offset: 0.09 + 0.06),
    _ => throw ArgumentError.value(type, 'type', 'is not a colour effect'),
  };

  /// [full] mixed with the identity by [intensity].
  static List<double> forEffect(EffectType type, double intensity) =>
      mix(identity, full(type), intensity.clamp(0.0, 1.0));

  /// The single matrix of every colour effect in [effects], applied in list
  /// order; `null` when there are none.
  static List<double>? combine(Iterable<ClipEffect> effects) {
    List<double>? result;
    for (final effect in effects) {
      if (effect.type.kind != EffectKind.colorMatrix) continue;
      final m = forEffect(effect.type, effect.intensity);
      result = result == null ? m : then(result, m);
    }
    return result == null ? null : List.unmodifiable(result);
  }

  /// Saturation [s] around Rec.709 luma: `(1 − s)·L + s·I`.
  static List<double> saturation(double s) => [
    for (var row = 0; row < 4; row++)
      for (var col = 0; col < 5; col++)
        row == 3
            ? identity[row * 5 + col]
            : col < 3
            ? (1 - s) * luma[col] + (row == col ? s : 0)
            : 0,
  ];

  /// Element-wise `a + (b − a)·t`.
  static List<double> mix(List<double> a, List<double> b, double t) => [
    for (var i = 0; i < 20; i++) a[i] + (b[i] - a[i]) * t,
  ];

  /// The matrix that applies [first] and then [second].
  static List<double> then(List<double> first, List<double> second) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = col == 4 ? second[row * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          sum += second[row * 5 + k] * first[k * 5 + col];
        }
        out[row * 5 + col] = sum;
      }
    }
    return out;
  }

  /// [m] applied to one colour, unclamped.
  static List<double> apply(
    List<double> m,
    double r,
    double g,
    double b, [
    double a = 1,
  ]) => [
    for (var row = 0; row < 4; row++)
      m[row * 5] * r +
          m[row * 5 + 1] * g +
          m[row * 5 + 2] * b +
          m[row * 5 + 3] * a +
          m[row * 5 + 4],
  ];

  /// [m] with its offsets scaled to 0…255, the form `ColorFilter.matrix`
  /// takes, for the preview.
  static List<double> withByteOffsets(List<double> m) => [
    for (var i = 0; i < 20; i++) i % 5 == 4 ? m[i] * 255 : m[i],
  ];

  static List<double> _tintedLuma(
    List<double> tint, {
    List<double> offsets = const [0, 0, 0],
  }) => [
    for (var row = 0; row < 3; row++) ...[
      for (final w in luma) tint[row] * w,
      0,
      offsets[row],
    ],
    0, 0, 0, 1, 0, //
  ];

  static List<double> _scaled(
    List<double> m,
    double gain, {
    required double offset,
  }) => [
    for (var i = 0; i < 20; i++)
      i >= 15
          ? m[i]
          : i % 5 == 4
          ? m[i] * gain + offset
          : m[i] * gain,
  ];
}
