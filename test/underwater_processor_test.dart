import 'dart:io';
import 'dart:typed_data';

import 'package:aqua_recover/core/app_version.dart';
import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/media/media_classifier.dart';
import 'package:aqua_recover/core/models/export_options.dart';
import 'package:aqua_recover/core/models/image_transform_settings.dart';
import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/media_edit_state.dart';
import 'package:aqua_recover/core/models/media_job.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/models/raw_video_descriptor.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/persistence/export_library_service.dart';
import 'package:aqua_recover/core/persistence/folder_export_service.dart';
import 'package:aqua_recover/core/processing/image_restoration_service.dart';
import 'package:aqua_recover/core/processing/image_transform_service.dart';
import 'package:aqua_recover/core/processing/video_restoration_service.dart';
import 'package:aqua_recover/core/processing/underwater_processor.dart';
import 'package:aqua_recover/core/workflow/editor_workflow.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/features/editor/widgets/app_license_page.dart';
import 'package:aqua_recover/features/editor/widgets/batch_edit_copy_sheet.dart';
import 'package:aqua_recover/features/editor/widgets/crop_browser.dart';
import 'package:aqua_recover/features/editor/widgets/adjustment_browser.dart';
import 'package:aqua_recover/features/editor/widgets/editor_bottom_panel.dart';
import 'package:aqua_recover/features/editor/widgets/editor_preview_stage.dart';
import 'package:aqua_recover/features/editor/widgets/editor_tool_rail.dart';
import 'package:aqua_recover/features/editor/widgets/exported_photo_preview.dart';
import 'package:aqua_recover/features/editor/widgets/gpu_preview_filter.dart';
import 'package:aqua_recover/features/editor/widgets/image_transform_preview.dart';
import 'package:aqua_recover/features/editor/widgets/preset_browser.dart';
import 'package:aqua_recover/features/editor/widgets/queue_overview_sheet.dart';
import 'package:aqua_recover/features/editor/widgets/restored_image_preview.dart';
import 'package:aqua_recover/features/editor/widgets/video_frame_preview_tile.dart';
import 'package:aqua_recover/features/library/export_library_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final localReferencePairIndices = _referencePairIndices();

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

  test('media edit values copy only to requested queue targets', () {
    const source = MediaEditState(
      settings: RestorationSettings(contrast: 1.31, saturation: 1.22),
      transform: ImageTransformSettings(
        aspectRatio: CropAspectRatio.square,
        quarterTurns: 1,
      ),
      lutProfile: LutProfile.coralWarm,
    );
    const originalTarget = MediaEditState();
    const untouched = MediaEditState(
      settings: RestorationSettings(contrast: .91),
    );
    final original = <String, MediaEditState>{
      'source': source,
      'target': originalTarget,
      'untouched': untouched,
    };

    final copied = copyMediaEditStateToTargets(
      states: original,
      sourceId: 'source',
      targetIds: const ['target'],
    );

    expect(copied['target']!.settings.contrast, 1.31);
    expect(copied['target']!.transform.aspectRatio, CropAspectRatio.square);
    expect(copied['target']!.transform.normalizedQuarterTurns, 1);
    expect(copied['target']!.lutProfile.kind, LutKind.coralWarm);
    expect(copied['untouched']!.settings.contrast, .91);
    expect(original['target']!.settings.contrast, 1.04);
  });

  test('None preset leaves pixels unchanged', () {
    final source = img.Image(width: 4, height: 4, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, 18 + x, 120 + y, 210 - x, 255);
      }
    }

    final output = const UnderwaterProcessor().restoreImage(
      source,
      RestorationPreset.none.settings,
    );
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final before = source.getPixel(x, y);
        final after = output.getPixel(x, y);
        expect(
          (after.r, after.g, after.b, after.a),
          (before.r, before.g, before.b, before.a),
        );
      }
    }
  });

  test('image crop settings produce normalized crops and pixel transforms', () {
    const square = ImageTransformSettings(aspectRatio: CropAspectRatio.square);
    final rect = square.normalizedCropRect(2);
    expect(rect.left, closeTo(.25, .0001));
    expect(rect.top, 0);
    expect(rect.width, closeTo(.5, .0001));
    expect(rect.height, 1);

    final source = img.Image(width: 8, height: 4, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, x * 20, y * 30, 0, 255);
      }
    }
    final cropped = const ImageTransformService().apply(source, square);
    expect(cropped.width, 4);
    expect(cropped.height, 4);
    expect(cropped.getPixel(0, 0).r, source.getPixel(2, 0).r);

    final rotated = const ImageTransformService().apply(
      source,
      const ImageTransformSettings(quarterTurns: 1),
    );
    expect(rotated.width, 4);
    expect(rotated.height, 8);
  });

  test('freeform crop and straightening preserve a filled output', () {
    const settings = ImageTransformSettings(
      aspectRatio: CropAspectRatio.freeform,
      customAspectRatio: 1.5,
      straightenDegrees: 18,
    );
    expect(settings.outputAspectRatio(2), 1.5);
    expect(settings.straightenCoverageScale(2), greaterThan(1));

    final source = img.Image(width: 180, height: 100, numChannels: 4)
      ..clear(img.ColorRgba8(20, 120, 180, 255));
    final output = const ImageTransformService().apply(source, settings);
    expect(output.width / output.height, closeTo(1.5, .03));
    for (final point in [
      (0, 0),
      (output.width - 1, 0),
      (0, output.height - 1),
      (output.width - 1, output.height - 1),
    ]) {
      expect(output.getPixel(point.$1, point.$2).a, greaterThan(0));
    }

    final restored = ImageTransformSettings.fromJson(settings.toJson());
    expect(restored.aspectRatio, CropAspectRatio.freeform);
    expect(restored.customAspectRatio, 1.5);
    expect(restored.straightenDegrees, 18);
  });

  test('preset strength preserves later manual offsets', () {
    final full = RestorationPreset.deep.settings;
    final manual = full.copyWith(contrast: full.contrast + .12);
    final half = manual.withPresetStrength(.5);
    final halfBase = RestorationPreset.deep.settingsAtStrength(.5);

    expect(half.preset, RestorationPreset.deep);
    expect(half.presetStrength, .5);
    expect(half.recovery, closeTo(full.recovery * .5, .0001));
    expect(half.contrast, closeTo(halfBase.contrast + .12, .0001));
  });

  test(
    'auto recovery moves reference pairs toward provided after images',
    () async {
      final processor = const UnderwaterProcessor();
      var relativeDeltaSum = 0.0;
      for (final i in localReferencePairIndices) {
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
        relativeDeltaSum += restoredDelta / beforeDelta;
        expect(
          restoredDelta,
          lessThan(beforeDelta * 0.65),
          reason: 'reference pair $i should move closer to the target after',
        );
      }
      expect(
        relativeDeltaSum / localReferencePairIndices.length,
        lessThan(0.38),
        reason: 'auto recovery should stay close across the complete set',
      );
    },
    skip: localReferencePairIndices.isEmpty
        ? 'Private local reference images are not installed.'
        : false,
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
      expect(
        VideoRestorationService.isBackendAvailableForOperatingSystem('ios'),
        isTrue,
      );
      expect(
        VideoRestorationService.isBackendAvailableForOperatingSystem(
          'macos',
          ffmpegAvailable: false,
        ),
        isFalse,
      );
      expect(
        VideoRestorationService.isBackendAvailableForOperatingSystem(
          'macos',
          ffmpegAvailable: true,
        ),
        isTrue,
      );
      expect(
        VideoRestorationService.isBackendAvailableForOperatingSystem('android'),
        isFalse,
      );
      expect(
        VideoRestorationService.backendUnavailableReason,
        isNot(contains('/Users/')),
      );
    },
  );

  test(
    'image restoration service restores bytes on a background path',
    () async {
      final source = img.Image(width: 8, height: 8, numChannels: 4);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgba(x, y, 20, 128, 188, 255);
        }
      }

      final restoredBytes = await const ImageRestorationService().restoreBytes(
        Uint8List.fromList(img.encodeJpg(source, quality: 95)),
        RestorationPreset.auto.settings,
      );
      final restored = img.decodeImage(restoredBytes);

      expect(restored, isNotNull);
      expect(restored!.width, source.width);
      expect(restored.height, source.height);
      expect(restored.getPixel(4, 4).r, greaterThan(source.getPixel(4, 4).r));
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

  test('export options preserve independent local and Photos destinations', () {
    const localOnly = ExportOptions();
    final photosOnly = localOnly.copyWith(
      keepLocalCopy: false,
      saveToPhotoLibrary: true,
    );

    expect(localOnly.keepLocalCopy, isTrue);
    expect(localOnly.saveToPhotoLibrary, isFalse);
    expect(photosOnly.keepLocalCopy, isFalse);
    expect(photosOnly.saveToPhotoLibrary, isTrue);
    expect(photosOnly.toJson()['keepLocalCopy'], isFalse);
    expect(photosOnly.toJson()['saveToPhotoLibrary'], isTrue);
    final normalizedPhotosOnly = localOnly.withKeepLocalCopy(false);
    expect(normalizedPhotosOnly.keepLocalCopy, isFalse);
    expect(normalizedPhotosOnly.saveToPhotoLibrary, isTrue);
    final normalizedLocalOnly = photosOnly.withPhotoLibrary(false);
    expect(normalizedLocalOnly.keepLocalCopy, isTrue);
    expect(normalizedLocalOnly.saveToPhotoLibrary, isFalse);
    final filesOnly = localOnly.withFiles(true).withKeepLocalCopy(false);
    expect(filesOnly.keepLocalCopy, isFalse);
    expect(filesOnly.saveToPhotoLibrary, isFalse);
    expect(filesOnly.saveToFiles, isTrue);
    expect(filesOnly.toJson()['saveToFiles'], isTrue);
    expect(filesOnly.withFiles(false).keepLocalCopy, isTrue);
  });

  test('individual batch export is available for ready or failed items', () {
    expect(JobStatus.pending.canStartIndividualExport, isTrue);
    expect(JobStatus.failed.canStartIndividualExport, isTrue);
    expect(JobStatus.complete.canStartIndividualExport, isFalse);
    expect(JobStatus.processing.canStartIndividualExport, isFalse);
  });

  test('folder export copies files and avoids overwriting names', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aquarecover_folder_export_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final sourceDirectory = Directory('${directory.path}/source')..createSync();
    final destinationDirectory = Directory('${directory.path}/destination')
      ..createSync();
    final source = File('${sourceDirectory.path}/reef.jpg')
      ..writeAsBytesSync([1, 2, 3, 4]);
    const service = FolderExportService();

    final first = await service.copyToDirectory(
      sourcePath: source.path,
      directoryPath: destinationDirectory.path,
    );
    final second = await service.copyToDirectory(
      sourcePath: source.path,
      directoryPath: destinationDirectory.path,
    );

    expect(File(first).readAsBytesSync(), [1, 2, 3, 4]);
    expect(File(second).readAsBytesSync(), [1, 2, 3, 4]);
    expect(first, isNot(second));
    expect(second, endsWith('reef_2.jpg'));
  });

  test(
    'image restoration service applies crop settings before encoding',
    () async {
      final source = img.Image(width: 8, height: 4, numChannels: 4);
      source.clear(img.ColorRgba8(20, 120, 180, 255));
      final bytes = await const ImageRestorationService().restoreBytes(
        Uint8List.fromList(img.encodePng(source)),
        RestorationPreset.none.settings,
        exportOptions: const ExportOptions(imageFormat: ImageOutputFormat.png),
        transform: const ImageTransformSettings(
          aspectRatio: CropAspectRatio.square,
        ),
      );
      final transformed = img.decodePng(bytes);

      expect(transformed, isNotNull);
      expect(transformed!.width, 4);
      expect(transformed.height, 4);
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

  test('queue removal keeps the nearest remaining item selected', () {
    const jobs = [
      MediaJob(id: 'one', inputPath: '/one.jpg', kind: MediaKind.photo),
      MediaJob(id: 'two', inputPath: '/two.jpg', kind: MediaKind.photo),
      MediaJob(id: 'three', inputPath: '/three.jpg', kind: MediaKind.photo),
    ];

    final afterSelectedExport = removeMediaJobFromQueue(
      jobs: jobs,
      selectedIndex: 1,
      id: 'two',
    );
    expect(afterSelectedExport.jobs.map((job) => job.id), ['one', 'three']);
    expect(afterSelectedExport.selectedIndex, 1);

    final afterFinalExport = removeMediaJobFromQueue(
      jobs: [afterSelectedExport.jobs.last],
      selectedIndex: 0,
      id: 'three',
    );
    expect(afterFinalExport.jobs, isEmpty);
    expect(afterFinalExport.selectedIndex, 0);
  });

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
    expect(EditorToolGroup.effects.label, 'LUT');
    expect(
      activeEditorToolGroupsFor(MediaKind.photo),
      isNot(contains(EditorToolGroup.video)),
    );
    expect(activeEditorToolGroupsFor(MediaKind.photo), [
      EditorToolGroup.presets,
      EditorToolGroup.light,
      EditorToolGroup.crop,
      EditorToolGroup.effects,
    ]);
    expect(
      activeEditorToolGroupsFor(MediaKind.video),
      isNot(contains(EditorToolGroup.crop)),
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
    expect(updated.preset, RestorationPreset.auto);
    expect(updated.redRecovery, 1.8);

    expect(allImageAdjustmentControls, hasLength(19));
    expect(
      allImageAdjustmentControls.map((control) => control.id).toSet(),
      hasLength(19),
    );
    final waterCorrection = allImageAdjustmentControls.firstWhere(
      (control) => control.id == 'recovery',
    );
    expect(waterCorrection.label, 'Water correction');
    expect(waterCorrection.max, 1.5);
    expect(waterCorrection.help, contains('does not scale exposure'));
    expect(
      allImageAdjustmentControls.every(
        (control) => control.help?.isNotEmpty ?? false,
      ),
      isTrue,
    );
  });

  test('editor presets and compare mode use existing app state values', () {
    expect(editorPresetChoices, contains(RestorationPreset.auto));
    expect(editorPresetChoices.first, RestorationPreset.none);
    expect(editorPresetChoices, contains(RestorationPreset.deep));
    expect(
      RestorationPreset.deep.settings.redRecovery,
      greaterThan(RestorationPreset.auto.settings.redRecovery),
    );

    expect(EditorCompareMode.edited.toggled, EditorCompareMode.split);
    expect(EditorCompareMode.original.toggled, EditorCompareMode.split);
    expect(EditorCompareMode.split.toggled, EditorCompareMode.edited);
  });

  test('gpu preview matrix responds to color and hue settings', () {
    expect(GpuPreviewFilter.matrixFor(RestorationPreset.none.settings), const [
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
    final base = GpuPreviewFilter.matrixFor(RestorationPreset.auto.settings);
    final tuned = GpuPreviewFilter.matrixFor(
      RestorationPreset.auto.settings.copyWith(saturation: 1.8, hue: .12),
    );

    expect(base, hasLength(20));
    expect(tuned, hasLength(20));
    expect(tuned, isNot(equals(base)));
    expect(tuned[1].abs() + tuned[2].abs(), greaterThan(0));
  });

  test('photo preview renderer follows preview processor output', () async {
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
    final settings = RestorationPreset.deep.settings.copyWith(
      recovery: 1.5,
      redRecovery: 2.5,
      autoWhiteBalance: 1,
      contrastStretch: 1,
      saturation: 2.4,
      vibrance: .8,
    );

    final source = img.decodeImage(await file.readAsBytes())!;
    final exact = const UnderwaterProcessor().restoreImage(
      source,
      settings,
      quality: RestorationRenderQuality.preview,
    );
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
    expect(find.text('Restore underwater color'), findsOneWidget);
    expect(find.text('AquaRecover'), findsOneWidget);
    expect(find.byKey(const Key('start_brand_icon')), findsOneWidget);
    expect(find.byType(CupertinoSliverNavigationBar), findsNothing);
    expect(find.text('Import. Edit. Export.'), findsNothing);
    expect(find.text('Edit selected'), findsNothing);
  });

  testWidgets('about dialog opens the in-app license list', (tester) async {
    await tester.pumpWidget(const CupertinoApp(home: EditorPage()));

    await tester.tap(find.byKey(const Key('start_about')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Version $aquaRecoverVersion'), findsOneWidget);

    await tester.tap(find.text('Licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(AppLicensePage), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });

  testWidgets('queue overview shows thumbnails and removes pending items', (
    tester,
  ) async {
    final removed = <String>[];
    final jobs = [
      const MediaJob(
        id: 'active',
        inputPath: '/tmp/active.jpg',
        kind: MediaKind.photo,
        displayName: 'Active.jpg',
        status: JobStatus.processing,
      ),
      const MediaJob(
        id: 'pending',
        inputPath: '/tmp/pending.jpg',
        kind: MediaKind.photo,
        displayName: 'Pending.jpg',
      ),
    ];

    await tester.pumpWidget(
      CupertinoApp(
        home: QueueOverviewSheet(
          jobs: jobs,
          selectedJobId: 'active',
          busy: true,
          onSelected: (_) {},
          onRemove: (id) {
            removed.add(id);
            return true;
          },
        ),
      ),
    );

    expect(find.byKey(const Key('queue_overview_list')), findsOneWidget);
    expect(find.text('2 items in the queue'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('queue_remove_active')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('queue_remove_pending')));
    await tester.pump();

    expect(removed, ['pending']);
    expect(find.text('Pending.jpg'), findsNothing);
    expect(find.text('1 item in the queue'), findsOneWidget);
  });

  testWidgets('batch edit picker applies to selected targets', (tester) async {
    Set<String>? appliedIds;
    const source = MediaJob(
      id: 'source',
      inputPath: '/tmp/source.jpg',
      kind: MediaKind.photo,
      displayName: 'Source.jpg',
    );
    const targets = [
      MediaJob(
        id: 'one',
        inputPath: '/tmp/one.jpg',
        kind: MediaKind.photo,
        displayName: 'One.jpg',
      ),
      MediaJob(
        id: 'two',
        inputPath: '/tmp/two.jpg',
        kind: MediaKind.photo,
        displayName: 'Two.jpg',
      ),
    ];

    await tester.pumpWidget(
      CupertinoApp(
        home: BatchEditCopySheet(
          source: source,
          targets: targets,
          onApplySelected: (ids) async {
            appliedIds = ids;
            return false;
          },
          onApplyAll: () async => false,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('batch_edit_target_two')));
    await tester.pump();
    expect(find.text('Apply to 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('batch_edit_apply_selected')));
    await tester.pump();
    expect(appliedIds, {'two'});
  });

  testWidgets('start queue opens the selected photo in the editor', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'aquarecover_start_queue_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/queue-photo.jpg');
    file.writeAsBytesSync(
      img.encodeJpg(img.Image(width: 16, height: 12), quality: 90),
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: EditorPage(
          initialPaths: [file.path],
          libraryOnStart: true,
          inspectionService: const _FakeMediaInspectionService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('start_selected_media')), findsNothing);
    expect(find.byKey(const Key('start_local_exports')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Add or open media')).dy,
      lessThan(tester.getTopLeft(find.text('Queue')).dy),
    );
    final queueItem = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'start_queue_item_',
          ),
    );
    expect(queueItem, findsOneWidget);

    await tester.tap(queueItem);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('editor_review_export')), findsOneWidget);
  });

  testWidgets('copy to all requires confirmation and keeps per-photo edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync(
      'aquarecover_copy_edits_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final first = File('${directory.path}/first.jpg');
    final second = File('${directory.path}/second.jpg');
    final bytes = img.encodeJpg(img.Image(width: 16, height: 12), quality: 90);
    first.writeAsBytesSync(bytes);
    second.writeAsBytesSync(bytes);

    await tester.pumpWidget(
      CupertinoApp(
        home: EditorPage(
          initialPaths: [first.path, second.path],
          inspectionService: const _FakeMediaInspectionService(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    await tester.drag(
      find.byKey(const Key('preset_list')),
      const Offset(-220, 0),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('preset_deep')));
    await tester.pump();
    expect(find.text('Deep dive - Photo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor_next_item')));
    await tester.pump();
    expect(find.text('Auto - Photo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('editor_previous_item')));
    await tester.pump();
    expect(find.text('Deep dive - Photo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor_copy_edits')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Copy edits'), findsOneWidget);

    await tester.tap(find.byKey(const Key('batch_edit_apply_all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.text(
        'Die Einstellungen werden nun auf alle anderen Bilder angewendet.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('confirm_apply_edits_to_all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('editor_next_item')));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Deep dive - Photo'), findsOneWidget);
  });

  testWidgets('completed export shows only the saved photo', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'aquarecover_export_preview_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final exported = File('${directory.path}/exported.png');
    exported.writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 30)));

    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 380,
            child: ExportedPhotoPreview(
              path: exported.path,
              aspectRatio: 4 / 3,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final preview = find.byKey(const Key('exported_photo_preview'));
    expect(tester.getSize(preview).width, 360);
    expect(find.byKey(const Key('exported_photo_image')), findsOneWidget);
    expect(find.byType(CupertinoSlider), findsNothing);
    expect(find.text('Before / after'), findsNothing);
  });

  testWidgets('local export library opens and deletes an export', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'aquarecover_library_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/reef_aqua.png');
    file.writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    final item = LocalExportItem(
      path: file.path,
      kind: MediaKind.photo,
      sizeBytes: file.lengthSync(),
      modified: DateTime(2026, 8, 5),
    );
    final service = _FakeExportLibraryService([item]);

    await tester.pumpWidget(
      CupertinoApp(home: ExportLibraryPage(service: service)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Local Exports'), findsOneWidget);
    expect(find.text('reef_aqua.png'), findsOneWidget);

    await tester.tap(find.byKey(const Key('local_export_reef_aqua.png')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(ExportDetailPage), findsOneWidget);

    final deleteButton = find
        .byKey(const Key('delete_local_export'))
        .hitTestable();
    expect(deleteButton, findsOneWidget);
    await tester.tap(deleteButton);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(service.deleted, [item]);
    expect(find.text('No local exports yet.'), findsOneWidget);
  });

  testWidgets('local export library batch selects and deletes all exports', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'aquarecover_batch_library_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final items = <LocalExportItem>[];
    for (var index = 1; index <= 3; index++) {
      final file = File('${directory.path}/export_$index.png');
      file.writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
      items.add(
        LocalExportItem(
          path: file.path,
          kind: MediaKind.photo,
          sizeBytes: file.lengthSync(),
          modified: DateTime(2026, 8, index),
        ),
      );
    }
    final service = _FakeExportLibraryService(items);

    await tester.pumpWidget(
      CupertinoApp(home: ExportLibraryPage(service: service)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('local_export_selection_mode')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('local_export_export_1.png')));
    await tester.tap(find.byKey(const Key('local_export_export_2.png')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Delete 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete_selected_local_exports')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Delete'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(service.deleted.length, 2);
    expect(find.text('export_3.png'), findsOneWidget);
    expect(find.text('Delete all'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete_all_local_exports')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Delete all local exports?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(service.deleted.length, 3);
    expect(find.text('No local exports yet.'), findsOneWidget);
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
                if (!open)
                  EditorCollapsedPanelButton(
                    group: selected,
                    onPressed: () => setState(() => open = true),
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

    await tester.tap(find.byKey(const Key('editor_tool_light')));
    await tester.pumpAndSettle();
    expect(find.text('Adjust panel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor_tool_panel_close')));
    await tester.pumpAndSettle();
    expect(find.text('Adjust panel'), findsNothing);
    expect(find.byKey(const Key('editor_tool_panel_open')), findsOneWidget);
    expect(find.text('Open Adjust'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editor_tool_panel_open')));
    await tester.pumpAndSettle();
    expect(find.text('Adjust panel'), findsOneWidget);
  });

  testWidgets(
    'adjustment browser shows the active value once and uses a full-width slider',
    (tester) async {
      const width = 360.0;
      await tester.pumpWidget(
        CupertinoApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: AdjustmentBrowser(
                controls: allImageAdjustmentControls,
                settings: RestorationPreset.auto.settings,
                presetSettings: RestorationPreset.auto.settings,
                selectedId: 'recovery',
                onSelected: (_) {},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Water correction'), findsOneWidget);
      expect(find.text('118%'), findsOneWidget);
      final sliderWidth = tester.getSize(find.byType(CupertinoSlider)).width;
      expect(sliderWidth, width);
    },
  );

  testWidgets('adjustment bubble resets only its value to the preset base', (
    tester,
  ) async {
    final preset = RestorationPreset.deep.settingsAtStrength(.5);
    var settings = preset.copyWith(contrast: 1.4, saturation: 1.5);
    await tester.pumpWidget(
      CupertinoApp(
        home: StatefulBuilder(
          builder: (context, setState) => AdjustmentBrowser(
            controls: allImageAdjustmentControls,
            settings: settings,
            presetSettings: preset,
            selectedId: 'recovery',
            onSelected: (_) {},
            onChanged: (value) => setState(() => settings = value),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('adjustment_contrast')));
    await tester.pumpAndSettle();
    expect(settings.contrast, preset.contrast);
    expect(settings.saturation, 1.5);
    expect(settings.preset, RestorationPreset.deep);
  });

  testWidgets('presets scroll and keep their identity through adjustments', (
    tester,
  ) async {
    var settings = RestorationPreset.auto.settings;
    await tester.pumpWidget(
      CupertinoApp(
        home: StatefulBuilder(
          builder: (context, setState) => PresetBrowser(
            settings: settings,
            onChanged: (value) => setState(() => settings = value),
          ),
        ),
      ),
    );

    expect(find.text('Choose a preset'), findsNothing);
    expect(find.byKey(const Key('preset_list')), findsOneWidget);
    expect(find.byKey(const Key('preset_none')), findsOneWidget);
    expect(find.text('Auto Fix'), findsNothing);
    expect(find.text('Color correction'), findsNothing);

    await tester.tap(find.byKey(const Key('preset_deep')));
    await tester.pumpAndSettle();
    expect(settings.preset, RestorationPreset.deep);
    expect(
      find.textContaining('Deep dive: Stronger red recovery'),
      findsOneWidget,
    );

    settings = allImageAdjustmentControls
        .firstWhere((control) => control.id == 'contrast')
        .apply(settings, 1.2);
    expect(settings.preset, RestorationPreset.deep);
  });

  testWidgets('crop browser updates aspect, rotation, and reset', (
    tester,
  ) async {
    var settings = const ImageTransformSettings();
    await tester.pumpWidget(
      CupertinoApp(
        home: StatefulBuilder(
          builder: (context, setState) => CropBrowser(
            settings: settings,
            sourceAspectRatio: 4 / 3,
            onChanged: (value) => setState(() => settings = value),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Square'));
    await tester.pump();
    expect(settings.aspectRatio, CropAspectRatio.square);

    await tester.tap(find.byKey(const Key('crop_rotate_right')));
    await tester.pump();
    expect(settings.normalizedQuarterTurns, 1);

    await tester.tap(find.text('Free'));
    await tester.pump();
    expect(settings.aspectRatio, CropAspectRatio.freeform);
    expect(find.byKey(const Key('crop_freeform_ratio')), findsOneWidget);

    await tester.tap(find.byKey(const Key('crop_flip_horizontal')));
    await tester.pump();
    expect(settings.flipHorizontal, isTrue);

    await tester.tap(find.byKey(const Key('crop_reset')));
    await tester.pump();
    expect(settings.isIdentity, isTrue);
  });

  testWidgets('immersive split preview reserves space for editor tools', (
    tester,
  ) async {
    const inset = 220.0;
    const topInset = 112.0;
    final job = MediaJob(
      id: 'split-stage',
      inputPath: '/tmp/split-stage.raw',
      kind: MediaKind.photo,
      displayName: 'split-stage.raw',
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: SizedBox(
          width: 393,
          height: 760,
          child: EditorPreviewStage(
            job: job,
            settings: RestorationPreset.auto.settings,
            compareMode: EditorCompareMode.split,
            immersive: true,
            immersiveTopInset: topInset,
            immersiveBottomInset: inset,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding ==
                const EdgeInsets.fromLTRB(10, topInset, 10, inset),
      ),
      findsOneWidget,
    );
    expect(find.byType(ImageFiltered), findsWidgets);
  });

  testWidgets('preview Fit contains the image and Fill covers the viewport', (
    tester,
  ) async {
    BoxFit? observedFit;
    Widget preview(EditorPreviewFit previewFit) => CupertinoApp(
      home: SizedBox(
        width: 320,
        height: 480,
        child: ImageTransformPreview(
          settings: const ImageTransformSettings(),
          sourceAspectRatio: 4 / 3,
          previewFit: previewFit,
          builder: (fit, _) {
            observedFit = fit;
            return const ColoredBox(color: CupertinoColors.black);
          },
        ),
      ),
    );

    await tester.pumpWidget(preview(EditorPreviewFit.fit));
    expect(observedFit, BoxFit.contain);

    await tester.pumpWidget(preview(EditorPreviewFit.fill));
    expect(observedFit, BoxFit.cover);

    await tester.pumpWidget(
      CupertinoApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: ImageTransformPreview(
            settings: const ImageTransformSettings(
              aspectRatio: CropAspectRatio.square,
            ),
            sourceAspectRatio: 16 / 9,
            builder: (fit, _) {
              observedFit = fit;
              return const ColoredBox(color: CupertinoColors.black);
            },
          ),
        ),
      ),
    );
    expect(observedFit, BoxFit.cover);
  });

  testWidgets('preview zoom supports pinch inspection and resets by key', (
    tester,
  ) async {
    Future<void> pumpZoom(String resetKey) => tester.pumpWidget(
      CupertinoApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: EditorPreviewZoom(
            resetKey: resetKey,
            child: const ColoredBox(color: CupertinoColors.black),
          ),
        ),
      ),
    );

    await pumpZoom('photo-fit');

    var viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('editor_preview_zoom')),
    );
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 5);
    expect(viewer.panEnabled, isTrue);
    expect(viewer.scaleEnabled, isTrue);

    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );

    await pumpZoom('another-photo');
    viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('editor_preview_zoom')),
    );
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
  });

  testWidgets('holding the edited preview temporarily reveals the original', (
    tester,
  ) async {
    final job = MediaJob(
      id: 'hold-preview',
      inputPath: '/tmp/hold-preview.dng',
      kind: MediaKind.rawPhoto,
      displayName: 'hold-preview.dng',
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: SizedBox(
          width: 393,
          height: 700,
          child: EditorHoldPreview(
            compareMode: EditorCompareMode.edited,
            previewBuilder: (mode) => EditorPreviewStage(
              job: job,
              settings: RestorationPreset.auto.settings,
              compareMode: mode,
            ),
            heldIndicator: const Align(
              alignment: Alignment.topLeft,
              child: Text('Holding original'),
            ),
          ),
        ),
      ),
    );

    EditorPreviewStage stage() =>
        tester.widget<EditorPreviewStage>(find.byType(EditorPreviewStage));
    expect(stage().compareMode, EditorCompareMode.edited);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(EditorHoldPreview)),
    );
    await tester.pump(const Duration(milliseconds: 650));
    expect(stage().compareMode, EditorCompareMode.original);
    expect(find.text('Holding original'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(stage().compareMode, EditorCompareMode.edited);
    expect(find.text('Holding original'), findsNothing);
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

class _FakeExportLibraryService extends ExportLibraryService {
  _FakeExportLibraryService(this.items);

  final List<LocalExportItem> items;
  final List<LocalExportItem> deleted = [];

  @override
  Future<List<LocalExportItem>> load() async => [...items];

  @override
  Future<void> delete(LocalExportItem item) async {
    deleted.add(item);
    items.remove(item);
  }
}

class _FakeMediaInspectionService extends MediaInspectionService {
  const _FakeMediaInspectionService();

  @override
  Future<MediaMetadata> inspect(String path) => Future.value(
    MediaMetadata(
      path: path,
      fileName: File(path).uri.pathSegments.last,
      kind: MediaKind.photo,
      fileSizeBytes: 256,
      width: 16,
      height: 12,
    ),
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

List<int> _referencePairIndices() {
  final fixtureDirectory = Directory('test/img');
  if (!fixtureDirectory.existsSync()) return const [];
  final beforePattern = RegExp(r'^before(\d+)\.webp$');
  final afterPattern = RegExp(r'^after(\d+)\.webp$');
  final before = <int>{};
  final after = <int>{};
  for (final file in fixtureDirectory.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    final beforeMatch = beforePattern.firstMatch(name);
    if (beforeMatch != null) {
      before.add(int.parse(beforeMatch.group(1)!));
      continue;
    }
    final afterMatch = afterPattern.firstMatch(name);
    if (afterMatch != null) after.add(int.parse(afterMatch.group(1)!));
  }
  return before.intersection(after).toList()..sort();
}
