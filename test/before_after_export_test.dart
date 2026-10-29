import 'dart:io';
import 'dart:typed_data';

import 'package:aqua_recover/core/media/capture_metadata.dart';
import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/models/export_options.dart';
import 'package:aqua_recover/core/models/image_transform_settings.dart';
import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/before_after_compositor.dart';
import 'package:aqua_recover/core/processing/image_restoration_service.dart';
import 'package:aqua_recover/core/processing/image_transform_service.dart';
import 'package:aqua_recover/core/processing/still_render_pipeline.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/shared/widgets/app_tooltip.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _compositor = BeforeAfterCompositor();

img.Image _solid(int width, int height, img.Color color) => img.fill(
  img.Image(width: width, height: height),
  color: color,
);

final _blue = img.ColorRgb8(20, 90, 140);
final _warm = img.ColorRgb8(180, 120, 100);

List<int> _rgb(img.Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
}

/// A bluish underwater gradient, so restoration visibly changes it and any
/// crop or rotation is visible in the pixels.
img.Image _reef(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = 10 + pixel.x * 120 ~/ width
      ..g = 70 + pixel.y * 80 ~/ height
      ..b = 150;
  }
  return image;
}

void main() {
  group('before/after layout', () {
    test('landscape photos stack and portrait or square photos sit side by '
        'side', () {
      BeforeAfterArrangement arrangement(int width, int height) =>
          BeforeAfterCompositor.arrangementFor(
            BeforeAfterLayout.sideBySide,
            width: width,
            height: height,
          );
      expect(arrangement(3000, 2000), BeforeAfterArrangement.stacked);
      expect(arrangement(2000, 3000), BeforeAfterArrangement.sideBySide);
      expect(arrangement(2000, 2000), BeforeAfterArrangement.sideBySide);
      expect(
        BeforeAfterCompositor.arrangementFor(
          BeforeAfterLayout.split,
          width: 3000,
          height: 2000,
        ),
        BeforeAfterArrangement.split,
      );
    });

    test('composite sizes follow the arrangement with a thin gap', () {
      final landscape = _compositor.compose(
        before: _solid(300, 200, _blue),
        after: _solid(300, 200, _warm),
      );
      expect((landscape.width, landscape.height), (300, 402));
      // Original on top, restored below, white gap between.
      expect(_rgb(landscape, 150, 100), [20, 90, 140]);
      expect(_rgb(landscape, 150, 201), [255, 255, 255]);
      expect(_rgb(landscape, 150, 300), [180, 120, 100]);

      final portrait = _compositor.compose(
        before: _solid(200, 300, _blue),
        after: _solid(200, 300, _warm),
      );
      expect((portrait.width, portrait.height), (402, 300));
      expect(_rgb(portrait, 100, 150), [20, 90, 140]);
      expect(_rgb(portrait, 300, 150), [180, 120, 100]);
    });

    test('split keeps the photo size: original left, restored right', () {
      final split = _compositor.compose(
        before: _solid(300, 200, _blue),
        after: _solid(300, 200, _warm),
        layout: BeforeAfterLayout.split,
        labels: false,
      );
      expect((split.width, split.height), (300, 200));
      expect(_rgb(split, 40, 100), [20, 90, 140]);
      expect(_rgb(split, 150, 100), [255, 255, 255]);
      expect(_rgb(split, 260, 100), [180, 120, 100]);
    });

    test('large photos are scaled to the social size limit', () {
      final composite = const BeforeAfterCompositor(maxDimension: 500).compose(
        before: _solid(600, 400, _blue),
        after: _solid(600, 400, _warm),
      );
      // Stacked: two 375×250 panes and a 2 px gap.
      expect((composite.width, composite.height), (375, 502));
    });

    test('a before pane rounded differently is fitted to the restored one', () {
      final composite = _compositor.compose(
        before: _solid(201, 299, _blue),
        after: _solid(200, 300, _warm),
        labels: false,
      );
      expect((composite.width, composite.height), (402, 300));
      expect(_rgb(composite, 199, 299), [20, 90, 140]);
    });

    test('labels are small pills that can be turned off', () {
      final before = _solid(600, 400, _blue);
      final after = _solid(600, 400, _warm);
      final labelled = _compositor.compose(before: before, after: after);
      final plain = _compositor.compose(
        before: before,
        after: after,
        labels: false,
      );
      // Pill: 20 px tall, 12 px from the pane's bottom-left corner.
      const pillY = 400 - 12 - 10;
      expect(_rgb(plain, 15, pillY), [20, 90, 140]);
      final pill = _rgb(labelled, 15, pillY);
      expect(pill[2], lessThan(90), reason: 'darkened behind the label');
      // White text inside the pill.
      final row = [for (var x = 12; x < 120; x++) _rgb(labelled, x, pillY)];
      expect(row.any((rgb) => rgb.every((c) => c > 200)), isTrue);
      // The After label sits on the restored pane, below the gap.
      final afterPillY = 402 + 400 - 12 - 10;
      expect(_rgb(plain, 15, afterPillY), [180, 120, 100]);
      expect(_rgb(labelled, 15, afterPillY)[0], lessThan(120));
      // Labels stay small: nothing changes in the middle of either pane.
      expect(_rgb(labelled, 300, 200), [20, 90, 140]);
      expect(_rgb(labelled, 300, 602), [180, 120, 100]);
    });

    test('photos too small for a label stay unlabelled', () {
      final tiny = _compositor.compose(
        before: _solid(16, 12, _blue),
        after: _solid(16, 12, _warm),
        layout: BeforeAfterLayout.split,
      );
      expect(_rgb(tiny, 1, 11), [20, 90, 140]);
      expect(_rgb(tiny, 15, 11), [180, 120, 100]);
    });
  });

  group('before/after export', () {
    const settings = RestorationSettings();
    const transform = ImageTransformSettings(
      quarterTurns: 1,
      aspectRatio: CropAspectRatio.fourThree,
      zoom: 1.4,
      offsetX: .2,
    );

    test('before has the same crop and rotation but no restoration', () async {
      const pipeline = StillRenderPipeline();
      final source = _reef(120, 80);
      final bytes = Uint8List.fromList(img.encodePng(source));
      final output = await pipeline.renderEncoded(
        bytes,
        settings: settings,
        transform: transform,
        lutProfile: LutProfile.none,
        exportOptions: const ExportOptions(
          imageFormat: ImageOutputFormat.png,
          beforeAfter: true,
          beforeAfterLabels: false,
        ),
      );

      final composite = img.decodePng(output)!;
      final before = const ImageTransformService().apply(source, transform);
      final after = await pipeline.render(
        source,
        settings: settings,
        transform: transform,
      );
      expect(before.height, greaterThan(before.width));
      expect((after.width, after.height), (before.width, before.height));
      // Portrait after the quarter turn, so the panes sit side by side.
      expect(composite.height, after.height);
      expect(composite.width, after.width * 2 + 2);

      var restoredDiffers = false;
      for (var y = 0; y < after.height; y++) {
        for (var x = 0; x < after.width; x++) {
          expect(_rgb(composite, x, y), _rgb(before, x, y));
          final restored = _rgb(composite, after.width + 2 + x, y);
          expect(restored, _rgb(after, x, y));
          if (restored.toString() != _rgb(before, x, y).toString()) {
            restoredDiffers = true;
          }
        }
      }
      expect(restoredDiffers, isTrue);
    });

    test('a JPEG comparison keeps only the capture date', () async {
      final source = _reef(60, 40);
      source.exif.imageIfd
        ..make = 'OM Digital Solutions'
        ..model = 'TG-7';
      source.exif.exifIfd
        ..[0x9003] = img.IfdValueAscii('2026:03:14 10:15:30')
        ..[0x9011] = img.IfdValueAscii('+07:00')
        ..[0x8827] = img.IfdValueShort(400);
      source.exif.gpsIfd[0x0001] = img.IfdValueAscii('S');
      final bytes = Uint8List.fromList(img.encodeJpg(source));

      final kept = await const StillRenderPipeline().renderEncoded(
        bytes,
        settings: settings,
        exportOptions: const ExportOptions(
          stripMetadata: false,
          beforeAfter: true,
        ),
      );
      final exif = img.decodeJpgExif(kept)!;
      expect(
        CaptureMetadata.captureDate(exif),
        DateTime.utc(2026, 3, 14, 3, 15, 30),
      );
      expect(exif.imageIfd.make, isNull);
      expect(exif.imageIfd.model, isNull);
      expect(exif.exifIfd.containsKey(0x8827), isFalse);
      expect(exif.gpsIfd.isEmpty, isTrue);
      final decoded = img.decodeJpg(kept)!;
      expect(exif.exifIfd[0xA002]!.toInt(), decoded.width);
      expect((decoded.width, decoded.height), (60, 82));

      final stripped = await const StillRenderPipeline().renderEncoded(
        bytes,
        settings: settings,
        exportOptions: const ExportOptions(beforeAfter: true),
      );
      final none = img.decodeJpgExif(stripped);
      expect(none == null || none.isEmpty, isTrue);
    });

    test('export options carry the comparison settings', () {
      const options = ExportOptions(
        beforeAfter: true,
        beforeAfterLayout: BeforeAfterLayout.split,
        beforeAfterLabels: false,
      );
      final restored = ExportOptions.fromJson(options.toJson());
      expect(restored.beforeAfter, isTrue);
      expect(restored.beforeAfterLayout, BeforeAfterLayout.split);
      expect(restored.beforeAfterLabels, isFalse);

      final defaults = ExportOptions.fromJson(const {});
      expect(defaults.beforeAfter, isFalse);
      expect(defaults.beforeAfterLayout, BeforeAfterLayout.sideBySide);
      expect(defaults.beforeAfterLabels, isTrue);
      for (final preset in ExportPreset.values) {
        expect(preset.options.beforeAfter, isFalse);
      }
    });
  });

  group('export settings', () {
    testWidgets('Before/After has a tooltip and reaches the photo export', (
      tester,
    ) async {
      _configurePhoneViewport(tester);
      final directory = Directory.systemTemp.createTempSync(
        'aquarecover_before_after_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}/reef.jpg')
        ..writeAsBytesSync(img.encodeJpg(_reef(16, 12), quality: 90));
      final imageService = _RecordingImageRestorationService();

      await _pumpExportPage(
        tester,
        paths: [input.path],
        inspectionService: const _PhotoInspectionService(),
        imageService: imageService,
      );

      final toggle = find.byKey(const Key('export_before_after'));
      await tester.ensureVisible(toggle);
      expect(
        _tooltipFor(tester, toggle),
        contains('original and the restored'),
      );
      expect(find.byKey(const Key('export_before_after_layout')), findsNothing);

      await tester.tap(toggle);
      await tester.pump();
      final layout = find.byKey(const Key('export_before_after_layout'));
      final labels = find.byKey(const Key('export_before_after_labels'));
      expect(layout, findsOneWidget);
      expect(find.text('Side by side'), findsOneWidget);
      expect(find.text('Split'), findsWidgets);
      expect(_tooltipFor(tester, layout), startsWith('Side by side'));
      expect(_tooltipFor(tester, labels), contains('labels'));

      await tester.tap(
        find.descendant(of: layout, matching: find.text('Split')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_tooltipFor(tester, layout), startsWith('Split'));
      await tester.ensureVisible(labels);
      await tester.tap(labels);
      await tester.pump();

      // A preset changes format and quality but keeps the comparison.
      await tester.ensureVisible(find.text('Social'));
      await tester.tap(find.text('Social'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.ensureVisible(find.byKey(const Key('export_commit')));
      await tester.tap(find.byKey(const Key('export_commit')));
      await tester.pump();
      await tester.pump();

      final options = imageService.options.single;
      expect(options.beforeAfter, isTrue);
      expect(options.beforeAfterLayout, BeforeAfterLayout.split);
      expect(options.beforeAfterLabels, isFalse);
      expect(options.imageFormat, ExportPreset.social.imageFormat);
    });

    testWidgets('a video-only export does not offer Before/After', (
      tester,
    ) async {
      _configurePhoneViewport(tester);
      final directory = Directory.systemTemp.createTempSync(
        'aquarecover_before_after_video_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final clip = File('${directory.path}/dive.mp4')..writeAsBytesSync([0]);

      await _pumpExportPage(
        tester,
        paths: [clip.path],
        inspectionService: const _VideoInspectionService(),
      );
      await tester.ensureVisible(find.text('Keep video audio'));
      expect(find.byKey(const Key('export_before_after')), findsNothing);
    });
  });
}

String _tooltipFor(WidgetTester tester, Finder control) {
  final tooltip = find.ancestor(of: control, matching: find.byType(AppTooltip));
  expect(tooltip, findsWidgets);
  return tester.widget<AppTooltip>(tooltip.first).message;
}

void _configurePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpExportPage(
  WidgetTester tester, {
  required List<String> paths,
  required MediaInspectionService inspectionService,
  ImageRestorationService imageService = const ImageRestorationService(),
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: EditorPage(
        initialPaths: paths,
        reviewExportOnStart: true,
        inspectionService: inspectionService,
        imageService: imageService,
      ),
    ),
  );
  for (var index = 0; index < 7; index++) {
    await tester.pump();
  }
}

class _PhotoInspectionService extends MediaInspectionService {
  const _PhotoInspectionService();

  @override
  Future<MediaMetadata> inspect(String path) async => MediaMetadata(
    path: path,
    fileName: File(path).uri.pathSegments.last,
    kind: MediaKind.photo,
    fileSizeBytes: 256,
    width: 16,
    height: 12,
  );
}

class _VideoInspectionService extends MediaInspectionService {
  const _VideoInspectionService();

  @override
  Future<MediaMetadata> inspect(String path) async => MediaMetadata(
    path: path,
    fileName: File(path).uri.pathSegments.last,
    kind: MediaKind.video,
    fileSizeBytes: 256,
    width: 1920,
    height: 1080,
    duration: const Duration(seconds: 20),
  );
}

class _RecordingImageRestorationService extends ImageRestorationService {
  final options = <ExportOptions>[];

  @override
  Future<String> restoreFile(
    String inputPath,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
    ImageTransformSettings transform = const ImageTransformSettings(),
    String? metadataSourcePath,
  }) async {
    options.add(exportOptions);
    return inputPath;
  }
}
