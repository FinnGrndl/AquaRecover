import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_render_plan.dart';
import 'package:aqua_recover/core/timeline/timeline_textures.dart';
import 'package:flutter_test/flutter_test.dart';

/// A decoded PNG with straight-alpha pixels.
class _Png {
  _Png(this.width, this.height, this.pixels);

  static Future<_Png> decode(Uint8List bytes) async {
    expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final png = _Png(image.width, image.height, data!);
    image.dispose();
    codec.dispose();
    return png;
  }

  final int width, height;
  final ByteData pixels;

  int channel(int x, int y, int c) => pixels.getUint8((y * width + x) * 4 + c);

  int alpha(int x, int y) => channel(x, y, 3);

  int get maxAlpha {
    var best = 0;
    for (var i = 3; i < pixels.lengthInBytes; i += 4) {
      final a = pixels.getUint8(i);
      if (a > best) best = a;
    }
    return best;
  }

  double meanAlpha(int fromRow, int toRow) {
    var sum = 0;
    for (var y = fromRow; y < toRow; y++) {
      for (var x = 0; x < width; x++) {
        sum += alpha(x, y);
      }
    }
    return sum / ((toRow - fromRow) * width);
  }

  /// Whether every visible pixel has the colour [rgb].
  bool visibleAre(int rgb) {
    for (var i = 0; i < pixels.lengthInBytes; i += 4) {
      if (pixels.getUint8(i + 3) < 16) continue;
      final value =
          pixels.getUint8(i) << 16 |
          pixels.getUint8(i + 1) << 8 |
          pixels.getUint8(i + 2);
      if ((value >> 16 & 0xFF) - (rgb >> 16 & 0xFF) case final d
          when d.abs() > 8) {
        return false;
      }
      if ((value & 0xFF) - (rgb & 0xFF) case final d when d.abs() > 8) {
        return false;
      }
    }
    return true;
  }
}

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('titles', () {
    for (final style in TitleStyle.values) {
      test('${style.name} PNG matches measureTitle', () async {
        final spec = TitleSpec(text: 'Blue Hole\nDahab · 32 m', style: style);
        final size = measureTitle(spec, canvasWidth: 1920, canvasHeight: 1080);
        expect(size.width, greaterThan(0));
        expect(size.width, lessThanOrEqualTo(1920 * 0.9 + 1));
        final png = await _Png.decode(
          await rasterizeTitle(spec, canvasWidth: 1920, canvasHeight: 1080),
        );
        expect(png.width, size.width.round());
        expect(png.height, size.height.round());
        expect(png.maxAlpha, 255);
        expect(
          titleAspectRatio(spec, 1920, 1080),
          closeTo(png.width / png.height, 1e-9),
        );
      });
    }

    test('rasterises at the requested width with the same aspect', () async {
      const spec = TitleSpec(text: 'Manta', style: TitleStyle.boldBox);
      final size = measureTitle(spec, canvasWidth: 1280, canvasHeight: 720);
      final png = await _Png.decode(
        await rasterizeTitle(
          spec,
          canvasWidth: 1280,
          canvasHeight: 720,
          width: 900,
        ),
      );
      expect(png.width, 900);
      expect(png.width / png.height, closeTo(size.aspectRatio, 0.02));
    });

    test('font size follows the canvas height', () {
      const spec = TitleSpec(text: 'Wreck');
      final small = measureTitle(spec, canvasWidth: 1280, canvasHeight: 720);
      final large = measureTitle(spec, canvasWidth: 2560, canvasHeight: 1440);
      expect(large.height, closeTo(small.height * 2, 2));
    });

    test('dive stamps use a smaller second line', () {
      final one = measureTitle(
        const TitleSpec(text: 'Blue Hole', style: TitleStyle.diveStamp),
        canvasWidth: 1920,
        canvasHeight: 1080,
      );
      final two = measureTitle(
        const TitleSpec(text: 'Blue Hole\n32 m', style: TitleStyle.diveStamp),
        canvasWidth: 1920,
        canvasHeight: 1080,
      );
      expect(two.height, greaterThan(one.height * 1.3));
      expect(two.height, lessThan(one.height * 2));
    });

    test(
      'a boxed title fills its corners-free box with the box colour',
      () async {
        const spec = TitleSpec(
          text: 'Reef',
          style: TitleStyle.boldBox,
          backgroundColor: 0xFF0A84FF,
          color: 0xFFFFFFFF,
        );
        final png = await _Png.decode(
          await rasterizeTitle(spec, canvasWidth: 1920, canvasHeight: 1080),
        );
        // Middle of the left padding: box colour, opaque.
        final y = png.height ~/ 2, x = 8;
        expect(png.alpha(x, y), 255);
        expect(png.channel(x, y, 2), closeTo(0xFF, 2));
        expect(png.channel(x, y, 0), closeTo(0x0A, 2));
        // Rounded corner stays transparent.
        expect(png.alpha(0, 0), 0);
      },
    );

    test('long text wraps inside the canvas', () {
      final size = measureTitle(
        TitleSpec(text: List.filled(40, 'coral').join(' ')),
        canvasWidth: 1080,
        canvasHeight: 1920,
      );
      expect(size.width, lessThanOrEqualTo(1080 * 0.9 + 1));
      expect(size.height, greaterThan(1920 * 0.075 * 2));
    });
  });

  group('effect textures', () {
    test('vignette is black with a smoothstep falloff', () async {
      final png = await _Png.decode(
        await rasterizeEffectTexture(EffectType.vignette, 0.5, 320, 180),
      );
      expect((png.width, png.height), (320, 180));
      expect(png.alpha(160, 90), 0);
      final corner = 255 * 0.5 * _smoothstep(0.35, 1.05, 1);
      expect(png.alpha(0, 0), closeTo(corner, 8));
      // Halfway to the corner: d ≈ 0.5.
      expect(
        png.alpha(80, 45),
        closeTo(255 * 0.5 * _smoothstep(0.35, 1.05, 0.5), 8),
      );
      expect(png.visibleAre(0x000000), isTrue);
    });

    test('cinema bars letterbox landscape to 2.39:1', () async {
      final png = await _Png.decode(
        await rasterizeEffectTexture(EffectType.cinemaBars, 1, 1920, 1080),
      );
      final bar = TimelineCompiler.cinemaBarHeight(1, 1920, 1080).round();
      expect(bar, 138);
      expect(png.alpha(10, bar - 1), 255);
      expect(png.alpha(10, bar), 0);
      expect(png.alpha(10, 1080 - bar), 255);
      expect(png.alpha(10, 1079 - bar), 0);
      expect(png.visibleAre(0x000000), isTrue);
    });

    test('cinema bars cover 10 % × intensity on portrait', () async {
      expect(TimelineCompiler.cinemaBarHeight(0.5, 1080, 1920), 96);
      final png = await _Png.decode(
        await rasterizeEffectTexture(EffectType.cinemaBars, 0.5, 108, 192),
      );
      expect(png.alpha(50, 9), 255);
      expect(png.alpha(50, 10), 0);
    });

    test('sun rays are white, soft, and capped at 0.55 × intensity', () async {
      final png = await _Png.decode(
        await rasterizeEffectTexture(EffectType.sunRays, 0.8, 416, 234),
      );
      expect((png.width, png.height), (416, 234));
      expect(png.maxAlpha, lessThanOrEqualTo((0.55 * 0.8 * 255).round() + 1));
      expect(png.maxAlpha, greaterThan(0.25 * 0.8 * 255));
      expect(png.visibleAre(0xFFFFFF), isTrue);
      // Rays fade out towards the bottom.
      expect(png.meanAlpha(0, 60), greaterThan(png.meanAlpha(200, 234)));
    });

    test('caustics are fast, white, and stronger at the top', () async {
      final watch = Stopwatch()..start();
      final bytes = await rasterizeEffectTexture(
        EffectType.caustics,
        1,
        1920,
        1080,
      );
      watch.stop();
      final png = await _Png.decode(bytes);
      expect((png.width, png.height), (1920, 1080));
      expect(png.maxAlpha, lessThanOrEqualTo((0.45 * 255).round() + 1));
      expect(png.maxAlpha, greaterThan(0.3 * 255));
      expect(png.visibleAre(0xFFFFFF), isTrue);
      expect(png.meanAlpha(0, 100), greaterThan(png.meanAlpha(980, 1080)));
      // Generous bound for CI machines; typically well under 300 ms.
      expect(watch.elapsedMilliseconds, lessThan(3000));
    });

    test('other effects have no texture', () {
      expect(
        () => rasterizeEffectTexture(EffectType.mono, 1, 10, 10),
        throwsArgumentError,
      );
    });

    test('rasterizeGenerated dispatches by spec', () async {
      final title = await _Png.decode(
        await rasterizeGenerated(
          const TitleTexture(
            TitleSpec(text: 'Nudibranch'),
            width: 400,
            canvasWidth: 1920,
            canvasHeight: 1080,
          ),
        ),
      );
      expect(title.width, 400);
      final texture = await _Png.decode(
        await rasterizeGenerated(
          const EffectTexture(EffectType.vignette, 0.5, 64, 36),
        ),
      );
      expect((texture.width, texture.height), (64, 36));
    });
  });

  group('GeneratedTextureCache', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('aq_textures');
    });
    tearDown(() => dir.delete(recursive: true));

    test('writes each spec once and reuses the file', () async {
      var calls = 0;
      final cache = GeneratedTextureCache(
        directory: () async => dir,
        rasterize: (spec) async {
          calls++;
          return rasterizeGenerated(spec);
        },
      );
      const spec = EffectTexture(EffectType.vignette, 0.5, 64, 36);
      final results = await Future.wait([
        cache.pathFor(spec),
        cache.pathFor(const EffectTexture(EffectType.vignette, 0.5, 64, 36)),
      ]);
      expect(results[0], results[1]);
      expect(calls, 1);
      expect(results[0], startsWith(dir.path));
      expect(results[0], endsWith('.png'));
      expect(File(results[0]).existsSync(), isTrue);
      await _Png.decode(File(results[0]).readAsBytesSync());

      // A new cache finds the file on disk without rasterising again.
      final again = GeneratedTextureCache(
        directory: () async => dir,
        rasterize: (spec) async {
          calls++;
          return rasterizeGenerated(spec);
        },
      );
      expect(await again.pathFor(spec), results[0]);
      expect(calls, 1);

      final other = await cache.pathFor(
        const EffectTexture(EffectType.vignette, 0.6, 64, 36),
      );
      expect(other, isNot(results[0]));
      expect(calls, 2);
    });

    test('names files by kind and a stable hash', () {
      const a = TitleTexture(
        TitleSpec(text: 'A'),
        width: 100,
        canvasWidth: 1920,
        canvasHeight: 1080,
      );
      const b = TitleTexture(
        TitleSpec(text: 'B'),
        width: 100,
        canvasWidth: 1920,
        canvasHeight: 1080,
      );
      final name = GeneratedTextureCache.fileNameFor(a);
      expect(name, matches(RegExp(r'^title_[0-9a-f]{16}\.png$')));
      expect(GeneratedTextureCache.fileNameFor(a), name);
      expect(GeneratedTextureCache.fileNameFor(b), isNot(name));
      expect(
        GeneratedTextureCache.fileNameFor(
          const EffectTexture(EffectType.caustics, 0.35, 10, 10),
        ),
        startsWith('caustics_'),
      );
    });

    test('a failed rasterisation is retried', () async {
      var fail = true;
      final cache = GeneratedTextureCache(
        directory: () async => dir,
        rasterize: (spec) async {
          if (fail) throw StateError('boom');
          return rasterizeGenerated(spec);
        },
      );
      const spec = EffectTexture(EffectType.cinemaBars, 1, 32, 18);
      await expectLater(cache.pathFor(spec), throwsStateError);
      fail = false;
      expect(File(await cache.pathFor(spec)).existsSync(), isTrue);
    });
  });
}
