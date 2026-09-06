import 'dart:async';
import 'dart:io';

import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/models/export_options.dart';
import 'package:aqua_recover/core/models/image_transform_settings.dart';
import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/image_restoration_service.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/features/editor/widgets/editor_preview_stage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets(
    'export preview switches between split and edited and reveals original on hold',
    (tester) async {
      _configurePhoneViewport(tester);
      final directory = Directory.systemTemp.createTempSync(
        'aquarecover_export_compare_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}/reef.jpg')
        ..writeAsBytesSync(
          img.encodeJpg(img.Image(width: 16, height: 12), quality: 90),
        );
      final imageService = _CountingImageRestorationService();

      await _pumpExportPage(
        tester,
        paths: [input.path],
        inspectionService: const _PhotoInspectionService(),
        imageService: imageService,
      );

      final preview = find.byKey(const Key('export_preview_stage'));
      final compare = find.byKey(const Key('export_preview_compare'));
      expect(compare, findsOneWidget);
      expect(_previewStage(tester).compareMode, EditorCompareMode.split);

      await tester.tap(compare);
      await tester.pump();
      expect(_previewStage(tester).compareMode, EditorCompareMode.edited);
      expect(imageService.calls, 0);

      final gesture = await tester.startGesture(tester.getCenter(preview));
      await tester.pump(const Duration(milliseconds: 550));
      expect(_previewStage(tester).compareMode, EditorCompareMode.original);
      await gesture.up();
      await tester.pump();
      expect(_previewStage(tester).compareMode, EditorCompareMode.edited);

      await tester.tap(compare);
      await tester.pump();
      expect(_previewStage(tester).compareMode, EditorCompareMode.split);
      expect(imageService.calls, 0);
    },
  );

  testWidgets('export preview control is shared by batch and video review', (
    tester,
  ) async {
    _configurePhoneViewport(tester);
    final directory = Directory.systemTemp.createTempSync(
      'aquarecover_export_compare_media_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final first = File('${directory.path}/one.mp4')..writeAsBytesSync([0]);
    final second = File('${directory.path}/two.mp4')..writeAsBytesSync([0]);

    await _pumpExportPage(
      tester,
      paths: [first.path, second.path],
      inspectionService: const _VideoInspectionService(),
    );

    final compare = find.byKey(const Key('export_preview_compare'));
    expect(compare, findsOneWidget);
    expect(_previewStage(tester).job.kind, MediaKind.video);
    expect(_previewStage(tester).compareMode, EditorCompareMode.split);
    await tester.tap(compare);
    await tester.pump();
    expect(_previewStage(tester).compareMode, EditorCompareMode.edited);
  });

  testWidgets('editor confirmation and export action use system blue', (
    tester,
  ) async {
    _configurePhoneViewport(tester);
    final directory = Directory.systemTemp.createTempSync(
      'aquarecover_export_button_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/reef.jpg')
      ..writeAsBytesSync(
        img.encodeJpg(img.Image(width: 16, height: 12), quality: 90),
      );
    final imageService = _BlockingImageRestorationService();

    await tester.pumpWidget(
      CupertinoApp(
        home: EditorPage(
          initialPaths: [input.path],
          inspectionService: const _PhotoInspectionService(),
          imageService: imageService,
        ),
      ),
    );
    await _pumpImports(tester);

    final reviewButton = find.byKey(const Key('editor_review_export'));
    expect(
      tester.widget<CupertinoButton>(reviewButton).color,
      CupertinoColors.activeBlue,
    );
    await tester.tap(reviewButton);
    await tester.pump();

    final exportButton = find.byKey(const Key('export_commit'));
    CupertinoButton button() => tester.widget<CupertinoButton>(exportButton);
    expect(button().color, CupertinoColors.activeBlue);
    expect(button().onPressed, isNotNull);

    await tester.tap(exportButton);
    await tester.pump();
    expect(imageService.calls, 1);
    expect(button().onPressed, isNull);
    expect(find.byKey(const Key('export_commit_progress')), findsOneWidget);
  });
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
  await _pumpImports(tester);
}

Future<void> _pumpImports(WidgetTester tester) async {
  for (var index = 0; index < 7; index++) {
    await tester.pump();
  }
}

EditorPreviewStage _previewStage(WidgetTester tester) => tester
    .widget<EditorPreviewStage>(find.byKey(const Key('export_preview_stage')));

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

class _CountingImageRestorationService extends ImageRestorationService {
  int calls = 0;

  @override
  Future<String> restoreFile(
    String inputPath,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
    ImageTransformSettings transform = const ImageTransformSettings(),
  }) async {
    calls++;
    return inputPath;
  }
}

class _BlockingImageRestorationService extends ImageRestorationService {
  final Completer<String> _result = Completer<String>();
  int calls = 0;

  @override
  Future<String> restoreFile(
    String inputPath,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
    ImageTransformSettings transform = const ImageTransformSettings(),
  }) {
    calls++;
    return _result.future;
  }
}
