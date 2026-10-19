import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _closeToList(List<double> expected, [double tolerance = 1e-9]) =>
    pairwiseCompare<double, double>(
      expected,
      (a, b) => (a - b).abs() <= tolerance,
      'within $tolerance of',
    );

void main() {
  test('catalogue matches the engine spec', () {
    // id, label, category, kind, animated, overlay, default.
    const table = [
      ('mono', 'Mono', 'look', 'colorMatrix', false, true, 1.0),
      ('sepia', 'Sepia', 'look', 'colorMatrix', false, true, 0.8),
      ('cyanotype', 'Cyanotype', 'look', 'colorMatrix', false, true, 0.8),
      ('deepBlue', 'Deep Blue', 'underwater', 'colorMatrix', false, true, 0.5),
      ('vivid', 'Vivid', 'look', 'colorMatrix', false, true, 0.5),
      ('faded', 'Faded Film', 'look', 'colorMatrix', false, true, 0.5),
      ('softFocus', 'Soft Focus', 'lens', 'filter', false, true, 0.4),
      ('clarity', 'Clarity', 'lens', 'filter', false, true, 0.4),
      ('grain', 'Film Grain', 'lens', 'filter', true, true, 0.3),
      ('vignette', 'Vignette', 'lens', 'layer', false, false, 0.5),
      ('cinemaBars', 'Cinema Bars', 'lens', 'layer', false, false, 1.0),
      ('sunRays', 'Sun Rays', 'underwater', 'layer', true, false, 0.4),
      ('caustics', 'Caustics', 'underwater', 'layer', true, false, 0.35),
      ('strobe', 'Strobe Flash', 'underwater', 'layer', true, false, 0.7),
      ('swell', 'Swell', 'motion', 'motion', true, false, 0.4),
      ('drift', 'Slow Drift', 'motion', 'motion', true, false, 0.5),
    ];
    expect(EffectType.values, hasLength(table.length));
    for (final (id, label, category, kind, animated, overlay, value) in table) {
      final type = EffectType.byId(id)!;
      expect(type.label, label);
      expect(type.category.name, category);
      expect(type.kind.name, kind);
      expect(type.animated, animated, reason: id);
      expect(type.overlayAllowed, overlay, reason: id);
      expect(type.defaultIntensity, value);
    }
    expect(EffectType.byId('nope'), isNull);
    expect(EffectType.values.where((t) => t.usesTexture).map((t) => t.id), [
      'vignette',
      'cinemaBars',
      'sunRays',
      'caustics',
    ]);
    expect(EffectType.inCategory(EffectCategory.motion), [
      EffectType.swell,
      EffectType.drift,
    ]);
  });

  group('colour matrices', () {
    test('zero intensity is the identity', () {
      for (final type in EffectType.values) {
        if (type.kind != EffectKind.colorMatrix) continue;
        expect(
          ColorMatrices.forEffect(type, 0),
          _closeToList(ColorMatrices.identity),
        );
      }
    });

    test('mono puts Rec.709 luma in every channel', () {
      final m = ColorMatrices.forEffect(EffectType.mono, 1);
      expect(
        ColorMatrices.apply(m, 1, 0, 0),
        _closeToList([.2126, .2126, .2126, 1]),
      );
      expect(ColorMatrices.apply(m, 0, 1, 0)[2], closeTo(.7152, 1e-12));
    });

    test('sepia rows are the tinted luma from the spec', () {
      final m = ColorMatrices.full(EffectType.sepia);
      expect(m.sublist(0, 3), _closeToList([.2275, .7653, .0773], 1e-4));
      expect(m.sublist(5, 8), _closeToList([.1573, .5292, .0534], 1e-4));
      expect(m.sublist(10, 13), _closeToList([.0914, .3075, .0310], 1e-4));
    });

    test('cyanotype tints luma blue with small offsets', () {
      final out = ColorMatrices.apply(
        ColorMatrices.full(EffectType.cyanotype),
        0,
        0,
        0,
      );
      expect(out, _closeToList([0, .02, .06, 1]));
      final white = ColorMatrices.apply(
        ColorMatrices.full(EffectType.cyanotype),
        1,
        1,
        1,
      );
      expect(white, _closeToList([.35, .77, 1.06, 1], 1e-9));
    });

    test('deep blue cuts red and lifts green and blue blacks', () {
      final m = ColorMatrices.full(EffectType.deepBlue);
      expect(ColorMatrices.apply(m, 0, 0, 0), _closeToList([0, .03, .05, 1]));
      expect(
        ColorMatrices.apply(m, 1, 1, 1),
        _closeToList([.78, .96 + .02 + .03, 1.04 + .05, 1]),
      );
      final half = ColorMatrices.forEffect(EffectType.deepBlue, 0.5);
      expect(ColorMatrices.apply(half, 1, 0, 0)[0], closeTo(0.89, 1e-12));
    });

    test('vivid saturates around luma, keeping greys', () {
      final m = ColorMatrices.full(EffectType.vivid);
      expect(
        ColorMatrices.apply(m, .4, .4, .4),
        _closeToList([.4, .4, .4, 1], 1e-12),
      );
      final out = ColorMatrices.apply(m, .8, .4, .2);
      final y = .2126 * .8 + .7152 * .4 + .0722 * .2;
      expect(out[0], closeTo(y + 1.35 * (.8 - y), 1e-12));
    });

    test('faded lowers contrast and lifts blacks', () {
      final m = ColorMatrices.full(EffectType.faded);
      expect(ColorMatrices.apply(m, 0, 0, 0), _closeToList([.15, .15, .15, 1]));
      expect(
        ColorMatrices.apply(m, 1, 1, 1),
        _closeToList([.97, .97, .97, 1], 1e-12),
      );
    });

    test('then applies the first matrix first, offsets included', () {
      final a = ColorMatrices.full(EffectType.cyanotype);
      final b = ColorMatrices.full(EffectType.deepBlue);
      final composed = ColorMatrices.then(a, b);
      final step = ColorMatrices.apply(a, .3, .6, .9);
      expect(
        ColorMatrices.apply(composed, .3, .6, .9),
        _closeToList(ColorMatrices.apply(b, step[0], step[1], step[2]), 1e-12),
      );
    });

    test('combine multiplies colour effects in list order', () {
      final mono = ClipEffect(EffectType.mono, intensity: .7);
      final blue = ClipEffect(EffectType.deepBlue, intensity: .5);
      final combined = ColorMatrices.combine([
        mono,
        ClipEffect(EffectType.vignette),
        blue,
      ])!;
      expect(
        combined,
        _closeToList(
          ColorMatrices.then(
            ColorMatrices.forEffect(EffectType.mono, .7),
            ColorMatrices.forEffect(EffectType.deepBlue, .5),
          ),
        ),
      );
      final reversed = ColorMatrices.combine([blue, mono])!;
      final difference = [
        for (var i = 0; i < 20; i++) (reversed[i] - combined[i]).abs(),
      ].reduce((a, b) => a > b ? a : b);
      expect(difference, greaterThan(1e-3));
      expect(ColorMatrices.combine([ClipEffect(EffectType.grain)]), isNull);
      expect(ColorMatrices.combine(const []), isNull);
    });

    test('byte offsets for Flutter colour filters', () {
      final m = ColorMatrices.withByteOffsets(
        ColorMatrices.full(EffectType.faded),
      );
      expect(m[4], closeTo(.15 * 255, 1e-9));
      expect(m[0], closeTo(ColorMatrices.full(EffectType.faded)[0], 1e-12));
    });
  });
}
