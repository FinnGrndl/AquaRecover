import 'dart:io';

import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/media/media_classifier.dart';
import 'package:aqua_recover/core/models/export_options.dart';
import 'package:aqua_recover/core/models/media_job.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/models/raw_video_descriptor.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/video_restoration_service.dart';
import 'package:aqua_recover/core/processing/underwater_processor.dart';
import 'package:aqua_recover/core/workflow/editor_workflow.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/features/editor/widgets/editor_bottom_panel.dart';
import 'package:aqua_recover/features/editor/widgets/editor_preview_stage.dart';
import 'package:aqua_recover/features/editor/widgets/editor_tool_rail.dart';
import 'package:aqua_recover/features/editor/widgets/gpu_preview_filter.dart';
import 'package:aqua_recover/features/editor/widgets/restored_image_preview.dart';
import 'package:aqua_recover/features/editor/widgets/video_frame_preview_tile.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('red channel is recovered for blue-green cast images', () {
    final source = img.Image(width: 12, height: 12, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, 24, 145, 188, 255);
      }
    }

    final output = const UnderwaterProcessor().restoreImage(
      source,
      const RestorationSettings(),
    );
    final before = source.getPixel(4, 4);
    final after = output.getPixel(4, 4);

    expect(after.r, greaterThan(before.r));
    expect(after.a, before.a);
  });

  test('auto recovery avoids red wash on open-water color casts', () {
    final source = img.Image(width: 12, height: 12, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, 20, 128, 188, 255);
      }
    }

    final output = const UnderwaterProcessor().restoreImage(
      source,
      RestorationPreset.auto.settings,
    );
    final before = source.getPixel(4, 4);
    final after = output.getPixel(4, 4);

    expect(after.r, greaterThan(before.r));
    expect(after.r, lessThan(after.b));
    expect(after.r, lessThan(after.g * 1.15));
  });

  test(
    'auto recovery moves reference pairs toward provided after images',
    () async {
      final processor = const UnderwaterProcessor();
      for (var i = 1; i <= 4; i++) {
        final before = img.decodeImage(
          await File('test/img/before$i.webp').readAsBytes(),
        );
        final target = img.decodeImage(
          await File('test/img/after$i.webp').readAsBytes(),
        );
        expect(before, isNotNull);
        expect(target, isNotNull);

        final resizedBefore = img.copyResize(
          before!,
          width: 240,
          interpolation: img.Interpolation.linear,
        );
        final resizedTarget = img.copyResize(
          target!,
          width: resizedBefore.width,
          height: resizedBefore.height,
          interpolation: img.Interpolation.linear,
        );
        final restored = processor.restoreImage(
          resizedBefore.clone(),
          RestorationPreset.auto.settings,
        );

        final beforeDelta = _meanAbsDelta(resizedBefore, resizedTarget);
        final restoredDelta = _meanAbsDelta(restored, resizedTarget);
        expect(
          restoredDelta,
          lessThan(beforeDelta * 0.75),
          reason: 'reference pair $i should move closer to the target after',
        );
      }
    },
  );

  test('video auto filter uses conservative red lift', () {
    final filter = RestorationPreset.auto.settings.ffmpegFilter;

    expect(filter, contains('colorbalance=rs=0.0585'));
    expect(filter, contains('bs=-0.0212'));
  });

  test('HEIC photos use platform decoding', () {
    expect(
      MediaClassifier.requiresPlatformImageDecode('/tmp/dive.HEIC'),
      isTrue,
    );
    expect(
      MediaClassifier.requiresPlatformImageDecode('/tmp/dive.jpg'),
      isFalse,
    );
  });

  test('raw video descriptor rejects unsafe dimensions', () {
    expect(
      () => const RawVideoDescriptor(
        width: 20000,
        height: 20000,
        frameRate: 30,
        pixelFormat: 'yuv420p',
      ).validateForProcessing(),
      throwsFormatException,
    );
  });

  test('raw video descriptor rejects unsupported pixel format', () {
    expect(
      () => const RawVideoDescriptor(
        width: 1920,
        height: 1080,
        frameRate: 30,
        pixelFormat: 'evil;rm -rf',
      ).validateForProcessing(),
      throwsFormatException,
    );
  });

  test(
    'video backend is supported on iOS through native AVFoundation export',
    () {
      expect(
        VideoRestorationService.isBackendSupportedForOperatingSystem('ios'),
        isTrue,
      );
      expect(
        VideoRestorationService.isBackendSupportedForOperatingSystem('macos'),
        isTrue,
      );
    },
  );

  test(
    'export preset quality does not change the color restoration preset',
    () {
      final settings = RestorationPreset.deep.settings.copyWith(
        jpegQuality: ExportPreset.social.jpegQuality,
      );

      expect(settings.preset, RestorationPreset.deep);
      expect(settings.jpegQuality, ExportPreset.social.jpegQuality);
    },
  );

  test('media inspection reads local image metadata', () async {
    final dir = await Directory.systemTemp.createTemp('aqua_recover_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/reef.jpg');
    final image = img.Image(width: 5, height: 3, numChannels: 4);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgba(x, y, 20, 140, 190, 255);
      }
    }
    await file.writeAsBytes(img.encodeJpg(image));

    final metadata = await const MediaInspectionService().inspect(file.path);

    expect(metadata.fileName, 'reef.jpg');
    expect(metadata.kind.label, 'Photo');
    expect(metadata.width, 5);
    expect(metadata.height, 3);
    expect(metadata.fileSizeBytes, greaterThan(0));
  });

  test(
    'media inspection reports unsupported and missing files cleanly',
    () async {
      final dir = await Directory.systemTemp.createTemp('aqua_recover_test_');
      addTearDown(() => dir.delete(recursive: true));
      final unsupported = File('${dir.path}/notes.txt');
      await unsupported.writeAsString('not media');

      expect(
        () => const MediaInspectionService().inspect(unsupported.path),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => const MediaInspectionService().inspect('${dir.path}/missing.jpg'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'workflow state gates edit and export steps until media is selected',
    () {
      const empty = EditorWorkflowState(
        step: EditorWorkflowStep.import,
        hasSelection: false,
      );
      expect(empty.canEnter(EditorWorkflowStep.import), isTrue);
      expect(empty.canEnter(EditorWorkflowStep.edit), isFalse);
      expect(empty.canEnter(EditorWorkflowStep.export), isFalse);
      expect(empty.canGoForward, isFalse);

      const selected = EditorWorkflowState(
        step: EditorWorkflowStep.edit,
        hasSelection: true,
      );
      expect(selected.canEnter(EditorWorkflowStep.export), isTrue);
      expect(selected.canGoBack, isTrue);
      expect(selected.canGoForward, isTrue);
      expect(selected.next, EditorWorkflowStep.export);

      const busy = EditorWorkflowState(
        step: EditorWorkflowStep.edit,
        hasSelection: true,
        busy: true,
      );
      expect(busy.canEnter(EditorWorkflowStep.import), isFalse);
      expect(busy.canEnter(EditorWorkflowStep.edit), isTrue);
    },
  );

  test(
    'export review helpers format media details and video frame positions',
    () {
      expect(MediaMetadata.formatBytes(1536), '1.50 KB');
      expect(
        MediaMetadata.formatDuration(const Duration(minutes: 2, seconds: 4)),
        '2:04',
      );
      expect(
        VideoFramePreviewTile.representativePositionFor(
          const Duration(seconds: 1),
        ),
        Duration.zero,
      );
      expect(
        VideoFramePreviewTile.representativePositionFor(
          const Duration(seconds: 8),
        ),
        const Duration(seconds: 2),
      );
      expect(
        VideoFramePreviewTile.representativePositionFor(
          const Duration(seconds: 20),
        ),
        const Duration(seconds: 3),
      );
    },
  );

  test('editor tool groups expose expected controls and media visibility', () {
    expect(
      activeEditorToolGroupsFor(MediaKind.photo),
      isNot(contains(EditorToolGroup.video)),
    );
    expect(
      activeEditorToolGroupsFor(MediaKind.video),
      contains(EditorToolGroup.video),
    );

    final colorIds = EditorToolGroup.color.adjustments
        .map((control) => control.id)
        .toList();
    expect(
      colorIds,
      containsAll([
        'red_recovery',
        'auto_white_balance',
        'saturation',
        'vibrance',
        'hue',
      ]),
    );

    final redRecovery = EditorToolGroup.color.adjustments.firstWhere(
      (control) => control.id == 'red_recovery',
    );
    final updated = redRecovery.apply(RestorationPreset.auto.settings, 1.8);
    expect(updated.preset, RestorationPreset.pro);
    expect(updated.redRecovery, 1.8);
  });

  test('editor presets and compare mode use existing app state values', () {
    expect(editorPresetChoices, contains(RestorationPreset.auto));
    expect(editorPresetChoices, contains(RestorationPreset.deep));
    expect(editorPresetChoices, isNot(contains(RestorationPreset.pro)));
    expect(
      RestorationPreset.deep.settings.redRecovery,
      greaterThan(RestorationPreset.auto.settings.redRecovery),
    );

    var mode = EditorCompareMode.edited;
    mode = EditorCompareMode.original;
    expect(mode.label, 'Original');
    mode = EditorCompareMode.split;
    expect(mode.label, 'Split');
  });

  test('gpu preview matrix responds to color and hue settings', () {
    final base = GpuPreviewFilter.matrixFor(RestorationPreset.auto.settings);
    final tuned = GpuPreviewFilter.matrixFor(
      RestorationPreset.auto.settings.asPro(saturation: 1.8, hue: .12),
    );

    expect(base, hasLength(20));
    expect(tuned, hasLength(20));
    expect(tuned, isNot(equals(base)));
    expect(tuned[1].abs() + tuned[2].abs(), greaterThan(0));
  });

  test('photo preview renderer follows export processor output', () async {
    final dir = await Directory.systemTemp.createTemp('aqua_preview_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/blue_water.jpg');
    final image = img.Image(width: 12, height: 12, numChannels: 4);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgba(x, y, 24, 145, 188, 255);
      }
    }
    await file.writeAsBytes(img.encodeJpg(image, quality: 96));
    final settings = RestorationPreset.deep.settings.asPro(
      recovery: 1.5,
      redRecovery: 2.5,
      autoWhiteBalance: 1,
      contrastStretch: 1,
      saturation: 2.4,
      vibrance: .8,
    );

    final source = img.decodeImage(await file.readAsBytes())!;
    final exact = const UnderwaterProcessor().restoreImage(source, settings);
    final previewBytes = await RestoredImagePreview.renderPreviewBytesForTest(
      path: file.path,
      settings: settings,
      maxDimension: 64,
    );
    final preview = img.decodeImage(previewBytes)!;
    final expected = exact.getPixel(4, 4);
    final rendered = preview.getPixel(4, 4);

    expect(rendered.r, closeTo(expected.r, 12));
    expect(rendered.g, closeTo(expected.g, 12));
    expect(rendered.b, closeTo(expected.b, 12));
  });

  testWidgets('editor page renders a controlled import state without media', (
    tester,
  ) async {
    await tester.pumpWidget(const CupertinoApp(home: EditorPage()));

    expect(find.text('No media selected'), findsNothing);
    expect(find.text('Import Files'), findsOneWidget);
    expect(find.text('Import media'), findsOneWidget);
    expect(find.text('Import. Edit. Export.'), findsNothing);
    expect(find.text('Edit selected'), findsNothing);
  });

  testWidgets('editor tool rail selects groups and bottom panel closes', (
    tester,
  ) async {
    var selected = EditorToolGroup.presets;
    var open = true;

    await tester.pumpWidget(
      CupertinoApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                EditorToolRail(
                  groups: activeEditorToolGroupsFor(MediaKind.photo),
                  selectedGroup: selected,
                  panelOpen: open,
                  onSelected: (group) => setState(() {
                    selected = group;
                    open = true;
                  }),
                ),
                EditorBottomPanel(
                  group: selected,
                  open: open,
                  height: 180,
                  onClose: () => setState(() => open = false),
                  child: Text('${selected.label} panel'),
                ),
              ],
            );
          },
        ),
      ),
    );

    expect(find.text('Presets panel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor_tool_color')));
    await tester.pumpAndSettle();
    expect(find.text('Color panel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor_tool_panel_close')));
    await tester.pumpAndSettle();
    expect(find.text('Color panel'), findsNothing);
  });

  testWidgets(
    'edit preview stage keeps placeholder preview and panel visible',
    (tester) async {
      final job = MediaJob(
        id: 'stage',
        inputPath: '/tmp/stage.raw',
        kind: MediaKind.rawPhoto,
        displayName: 'stage.raw',
      );

      await tester.pumpWidget(
        CupertinoApp(
          home: Center(
            child: SizedBox(
              width: 393,
              height: 760,
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: EditorPreviewStage(
                        job: job,
                        settings: RestorationPreset.deep.settings,
                        compareMode: EditorCompareMode.split,
                      ),
                    ),
                    EditorToolRail(
                      groups: activeEditorToolGroupsFor(MediaKind.photo),
                      selectedGroup: EditorToolGroup.light,
                      panelOpen: true,
                      onSelected: (_) {},
                    ),
                    EditorBottomPanel(
                      group: EditorToolGroup.light,
                      open: true,
                      height: 220,
                      onClose: () {},
                      child: const Text('Light controls'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byType(EditorPreviewStage), findsOneWidget);
      expect(find.text('Preview generated during export'), findsOneWidget);
      expect(find.text('Light controls'), findsOneWidget);
    },
  );
}

double _meanAbsDelta(img.Image a, img.Image b) {
  final width = a.width < b.width ? a.width : b.width;
  final height = a.height < b.height ? a.height : b.height;
  var sum = 0.0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      sum += (pa.r - pb.r).abs();
      sum += (pa.g - pb.g).abs();
      sum += (pa.b - pb.b).abs();
    }
  }
  return sum / (width * height * 3);
}
