import 'dart:io';
import 'dart:math' as math;

import 'package:aqua_recover/core/models/export_options.dart';
import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/preview_render_worker.dart';
import 'package:aqua_recover/core/processing/underwater_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _underwaterScene(int width, int height, {int seed = 7}) {
  final random = math.Random(seed);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final depth = y / height;
      final texture = random.nextInt(24);
      image.setPixelRgb(
        x,
        y,
        (24 + texture * (1 - depth)).round(),
        (110 + texture - depth * 30).round(),
        (150 + texture ~/ 2 + depth * 40).round(),
      );
    }
  }
  return image;
}

void main() {
  test('parallel restoration matches the sequential renderer', () async {
    final source = _underwaterScene(1300, 1200);
    const settings = RestorationSettings(hue: .04, vignette: .3);
    const processor = UnderwaterProcessor();
    final sequential = processor.restoreImage(source, settings);
    final parallel = await processor.restoreImageInParallel(
      source,
      settings,
      workers: 4,
    );
    expect(parallel.width, sequential.width);
    expect(parallel.height, sequential.height);
    expect(
      parallel.data!.toUint8List(),
      orderedEquals(sequential.data!.toUint8List()),
    );
  });

  test('parallel band count scales with work and cores', () {
    expect(UnderwaterProcessor.parallelBandCount(1000000, processors: 8), 1);
    expect(UnderwaterProcessor.parallelBandCount(24000000, processors: 1), 1);
    expect(UnderwaterProcessor.parallelBandCount(6000000, processors: 4), 4);
    expect(UnderwaterProcessor.parallelBandCount(48000000, processors: 32), 8);
  });

  test('16-bit images are restored on the 8-bit scale', () {
    final eight = _underwaterScene(32, 24);
    final sixteen = eight.convert(format: img.Format.uint16);
    const processor = UnderwaterProcessor();
    final fromEight = processor.restoreImage(
      eight,
      const RestorationSettings(),
    );
    final fromSixteen = processor.restoreImage(
      sixteen,
      const RestorationSettings(),
    );
    for (final point in [(3, 3), (16, 12), (30, 20)]) {
      final a = fromEight.getPixel(point.$1, point.$2);
      final b = fromSixteen.getPixel(point.$1, point.$2);
      expect((a.r - b.r).abs(), lessThanOrEqualTo(2));
      expect((a.g - b.g).abs(), lessThanOrEqualTo(2));
      expect((a.b - b.b).abs(), lessThanOrEqualTo(2));
    }
  });

  group('JSON round trips', () {
    test('restoration settings', () {
      final settings = RestorationPreset.deep.settings.copyWith(
        hue: .1,
        vignette: .4,
        jpegQuality: 81,
      );
      final restored = RestorationSettings.fromJson(settings.toJson());
      expect(restored.toJson(), settings.toJson());
    });

    test('restoration settings tolerate partial and legacy maps', () {
      final partial = RestorationSettings.fromJson({'exposure': .2});
      expect(partial.exposure, .2);
      expect(partial.recovery, const RestorationSettings().recovery);
      final legacy = RestorationSettings.fromJson({
        'preset': RestorationPreset.vivid.index,
        'contrast': double.nan,
      });
      expect(legacy.preset, RestorationPreset.vivid);
      expect(legacy.contrast, const RestorationSettings().contrast);
    });

    test('LUT profile and export options', () {
      final lut = LutProfile.customCube('/tmp/look.cube', intensity: .5);
      expect(LutProfile.fromJson(lut.toJson()).toJson(), lut.toJson());
      const options = ExportOptions(
        imageFormat: ImageOutputFormat.png,
        videoFormat: VideoOutputFormat.mov,
        keepAudio: false,
      );
      expect(ExportOptions.fromJson(options.toJson()).toJson(), {
        ...options.toJson(),
      });
    });
  });

  test('preview worker folds queued renders for the same file', () async {
    final directory = await Directory.systemTemp.createTemp('aqua-preview');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/scene.png');
    await file.writeAsBytes(img.encodePng(_underwaterScene(64, 48)));
    final worker = PreviewRenderWorker();
    addTearDown(worker.dispose);

    PreviewRenderRequest request(double exposure) => PreviewRenderRequest(
      path: file.path,
      settings: RestorationSettings(exposure: exposure).toJson(),
      lutProfile: LutProfile.none.toJson(),
      maxDimension: 32,
    );

    final first = worker.render(request(0));
    final second = worker.render(request(.1));
    final third = worker.render(request(.2));
    final results = await Future.wait([first, second, third]);

    for (final bytes in results) {
      final decoded = img.decodeJpg(bytes)!;
      expect(math.max(decoded.width, decoded.height), 32);
    }
    // The second request was replaced by the third while it was queued.
    expect(results[1], same(results[2]));
  });
}
