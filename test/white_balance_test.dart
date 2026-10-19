import 'dart:typed_data';

import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/underwater_processor.dart';
import 'package:aqua_recover/features/editor/widgets/gpu_preview_filter.dart';
import 'package:aqua_recover/features/editor/widgets/neutral_point_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _flat(int r, int g, int b, {int size = 32}) =>
    img.Image(width: size, height: size)..clear(img.ColorRgb8(r, g, b));

void main() {
  const processor = UnderwaterProcessor();

  test('temperature and tint round-trip and default to neutral', () {
    const settings = RestorationSettings(temperature: .4, tint: -.2);
    final restored = RestorationSettings.fromJson(settings.toJson());
    expect(restored.temperature, .4);
    expect(restored.tint, -.2);
    final legacy = RestorationSettings.fromJson({'preset': 'auto'});
    expect(legacy.temperature, 0);
    expect(legacy.tint, 0);
    expect(legacy.hasWhiteBalance, isFalse);
    expect(
      RestorationSettings.fromJson({'temperature': 7}).temperature,
      1,
      reason: 'out-of-range values are clamped',
    );
  });

  test('white balance alone is not an identity edit', () {
    final none = RestorationPreset.none.settings;
    expect(none.isIdentity, isTrue);
    expect(none.copyWith(tint: .1).isIdentity, isFalse);
    expect(
      none.copyWith(temperature: .5).ffmpegFilter,
      contains('colorchannelmixer=rr=1.1750:gg=1.0000:bb=0.8250'),
    );
  });

  test('the GPU preview matrix scales each channel row', () {
    final base = RestorationPreset.auto.settings;
    final plain = GpuPreviewFilter.matrixFor(base);
    final warm = GpuPreviewFilter.matrixFor(base.copyWith(temperature: 1));
    final gains = base.copyWith(temperature: 1).whiteBalanceGains;
    for (var col = 0; col < 5; col++) {
      expect(warm[col], closeTo(plain[col] * gains.r, 1e-9));
      expect(warm[5 + col], closeTo(plain[5 + col], 1e-9));
      expect(warm[10 + col], closeTo(plain[10 + col] * gains.b, 1e-9));
    }
  });

  test('the neutral point turns a flat colour grey', () {
    for (final settings in [
      RestorationPreset.none.settings,
      RestorationPreset.auto.settings,
      RestorationPreset.greenWater.settings,
    ]) {
      final source = _flat(150, 170, 140);
      final balance = processor.neutralBalance(source, settings, 150, 170, 140);
      final balanced = settings.copyWith(
        temperature: balance.temperature,
        tint: balance.tint,
      );
      final out = processor.restoreImage(source, balanced).getPixel(16, 16);
      final spread =
          [out.r, out.g, out.b].reduce((a, b) => a > b ? a : b) -
          [out.r, out.g, out.b].reduce((a, b) => a < b ? a : b);
      expect(spread, lessThanOrEqualTo(3), reason: '${settings.preset}: $out');
    }
  });

  test('parallel restore and video bake apply white balance too', () async {
    final source = _flat(90, 140, 170, size: 48);
    final settings = RestorationPreset.auto.settings.copyWith(
      temperature: .6,
      tint: .3,
    );
    final sequential = processor.restoreImage(source, settings);
    final parallel = await processor.restoreImageInParallel(
      source,
      settings,
      workers: 1,
    );
    expect(parallel.getPixel(10, 10), sequential.getPixel(10, 10));

    final plainLattice = processor.bakeColorLattice(
      source,
      RestorationPreset.auto.settings,
      size: 3,
    );
    final warmLattice = processor.bakeColorLattice(source, settings, size: 3);
    // The mid-grey lattice entry gets warmer and more magenta.
    const mid = (1 * 9 + 1 * 3 + 1) * 3;
    expect(warmLattice[mid], greaterThan(plainLattice[mid]));
    expect(warmLattice[mid + 1], lessThan(plainLattice[mid + 1]));
    expect(warmLattice[mid + 2], lessThan(plainLattice[mid + 2]));
  });

  testWidgets('tapping a point sets temperature and tint', (tester) async {
    const width = 60, height = 40;
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      final left = (i ~/ 4) % width < width / 2;
      rgba
        ..[i] = left ? 120 : 200
        ..[i + 1] = left ? 170 : 200
        ..[i + 2] = left ? 200 : 200
        ..[i + 3] = 255;
    }
    RestorationSettings? result;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () async {
              result = await Navigator.of(context).push<RestorationSettings>(
                CupertinoPageRoute(
                  builder: (_) => NeutralPointPicker(
                    path: 'unused.jpg',
                    settings: RestorationPreset.none.settings,
                    decoder: (_, _) async =>
                        (rgba: rgba, width: width, height: height),
                    previewBuilder: (_) =>
                        const ColoredBox(color: Color(0xff336699)),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Temperature 0  ·  Tint 0'), findsOneWidget);

    final canvas = tester.getRect(
      find.byKey(const Key('neutral_picker_canvas')),
    );
    // The image is letterboxed; tap a quarter in from the left on the
    // blue-cast half.
    final imageWidth = canvas.height * width / height;
    final imageLeft = canvas.center.dx - imageWidth / 2;
    await tester.tapAt(Offset(imageLeft + imageWidth * .25, canvas.center.dy));
    await tester.pump();
    final values = tester
        .widget<Text>(find.byKey(const Key('neutral_picker_values')))
        .data!;
    expect(values, isNot('Temperature 0  ·  Tint 0'));

    await tester.tap(find.byKey(const Key('neutral_picker_done')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.temperature, greaterThan(.5), reason: 'blue cast → warmer');
    expect(result!.tint, greaterThan(0), reason: 'green excess → magenta');
  });
}
