import 'dart:io';
import 'dart:typed_data';

import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/scene_analyzer.dart';
import 'package:aqua_recover/core/processing/scene_suggestion_service.dart';
import 'package:aqua_recover/features/editor/widgets/preset_browser.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

RgbaThumbnail _flat(int r, int g, int b, {int width = 40, int height = 30}) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba
      ..[i] = r
      ..[i + 1] = g
      ..[i + 2] = b
      ..[i + 3] = 255;
  }
  return (rgba: rgba, width: width, height: height);
}

void main() {
  test('RGBA analysis matches the image analysis', () {
    final image = img.Image(width: 64, height: 48);
    for (final pixel in image) {
      pixel
        ..r = 20 + pixel.x
        ..g = 90 + pixel.y
        ..b = 140;
    }
    final rgba = image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    const analyzer = SceneAnalyzer();
    final fromImage = analyzer.analyze(image);
    final fromRgba = analyzer.analyzeRgba(rgba, 64, 48);
    expect(fromRgba.meanR, closeTo(fromImage.meanR, 1e-9));
    expect(fromRgba.meanG, closeTo(fromImage.meanG, 1e-9));
    expect(fromRgba.meanB, closeTo(fromImage.meanB, 1e-9));
    expect(fromRgba.medianLuma, fromImage.medianLuma);
    expect(fromRgba.suggestedPreset, fromImage.suggestedPreset);
  });

  test('rejects buffers that are too short', () {
    expect(
      () => const SceneAnalyzer().analyzeRgba(Uint8List(10), 4, 4),
      throwsArgumentError,
    );
  });

  group('SceneSuggestionService', () {
    late Directory dir;
    late File photo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('suggest');
      photo = await File('${dir.path}/dive.jpg').writeAsBytes([1, 2, 3]);
    });

    tearDown(() => dir.delete(recursive: true));

    test('suggests green water and caches per file version', () async {
      var decodes = 0;
      final service = SceneSuggestionService(
        decoder: (path, max) async {
          decodes++;
          expect(max, 320);
          return _flat(30, 120, 90);
        },
      );
      final first = await service.suggest(photo.path, MediaKind.photo);
      expect(first?.waterType, WaterType.green);
      expect(first?.suggestedPreset, RestorationPreset.greenWater);
      await service.suggest(photo.path, MediaKind.photo);
      expect(decodes, 1);

      await photo.writeAsBytes([1, 2, 3, 4]);
      await service.suggest(photo.path, MediaKind.photo);
      expect(decodes, 2);
    });

    test('skips videos, RAW, missing files, and decode failures', () async {
      var decodes = 0;
      final service = SceneSuggestionService(
        decoder: (path, max) async {
          decodes++;
          throw const FormatException('bad');
        },
      );
      expect(await service.suggest(photo.path, MediaKind.video), isNull);
      expect(await service.suggest(photo.path, MediaKind.rawPhoto), isNull);
      expect(
        await service.suggest('${dir.path}/missing.jpg', MediaKind.photo),
        isNull,
      );
      expect(decodes, 0);
      expect(await service.suggest(photo.path, MediaKind.photo), isNull);
      expect(decodes, 1);
    });
  });

  testWidgets('engine decoder downsizes real files', (tester) async {
    final dir = Directory.systemTemp.createTempSync('engine');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/blue.png')
      ..writeAsBytesSync(
        img.encodePng(
          img.Image(width: 800, height: 400)..clear(img.ColorRgb8(10, 80, 150)),
        ),
      );
    final thumbnail = await tester.runAsync(
      () => SceneSuggestionService.decodeWithEngine(file.path, 320),
    );
    expect(thumbnail, isNotNull);
    expect((thumbnail!.width, thumbnail.height), (320, 160));
    expect(thumbnail.rgba.sublist(0, 3), [10, 80, 150]);
  });

  testWidgets('preset browser offers and applies the suggestion', (
    tester,
  ) async {
    final suggestion = const SceneAnalyzer().analyzeRgba(
      _flat(12, 70, 110).rgba,
      40,
      30,
    );
    expect(suggestion.suggestedPreset, RestorationPreset.deep);
    var settings = RestorationPreset.auto.settings;
    await tester.pumpWidget(
      CupertinoApp(
        home: StatefulBuilder(
          builder: (context, setState) => CupertinoPageScaffold(
            child: SingleChildScrollView(
              child: PresetBrowser(
                settings: settings,
                suggestion: suggestion,
                onChanged: (value) => setState(() => settings = value),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('preset_suggestion')), findsOneWidget);
    expect(find.textContaining('Blue water: Deep dive'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);

    await tester.tap(find.byKey(const Key('apply_preset_suggestion')));
    await tester.pump();
    expect(settings.preset, RestorationPreset.deep);
    expect(
      settings.presetStrength,
      closeTo(suggestion.suggestedStrength, 1e-9),
    );
    expect(find.text('Applied'), findsOneWidget);
  });
}
