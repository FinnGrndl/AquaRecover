import 'dart:io';

import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/models/export_options.dart';
import 'package:aqua_recover/core/models/image_transform_settings.dart';
import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/persistence/export_library_service.dart';
import 'package:aqua_recover/core/platform/share_service.dart';
import 'package:aqua_recover/core/processing/image_restoration_service.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_project_store.dart';
import 'package:aqua_recover/core/timeline/timeline_render_service.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/library/export_library_page.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:aqua_recover/shared/widgets/app_tooltip.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('ShareService.supportsFileSharing', () {
    test('Apple platforms and Android share files', () {
      for (final os in ['ios', 'android', 'macos']) {
        expect(ShareService.supportsFileSharing(operatingSystem: os), isTrue);
      }
    });

    test('Linux has no file share sheet', () {
      expect(
        ShareService.supportsFileSharing(operatingSystem: 'linux'),
        isFalse,
      );
    });

    test('Windows shares files from build 1809', () {
      bool windows(String version) => ShareService.supportsFileSharing(
        operatingSystem: 'windows',
        operatingSystemVersion: version,
      );
      expect(windows('"Windows 10 Pro" 10.0 (Build 17134)'), isFalse);
      expect(windows('"Windows 10 Pro" 10.0 (Build 17763)'), isTrue);
      expect(windows('"Windows 11 Home" 10.0 (Build 26100)'), isTrue);
      expect(windows(''), isTrue);
      expect(ShareService.windowsBuild('10.0 (Build 19045)'), 19045);
      expect(ShareService.windowsBuild('10.0'), isNull);
    });
  });

  group('photo export', () {
    testWidgets('offers Share for the exported photo', (tester) async {
      final fixture = await _ExportFixture.create(tester, count: 1);
      final share = _FakeShare();
      await fixture.pumpEditor(tester, share);

      await tester.tap(find.byKey(const Key('export_commit')));
      await _settle(tester);

      final button = find.byKey(const Key('share_exports'));
      expect(button, findsOneWidget);
      expect(_tooltipOf(tester, button), 'Share the exported file');
      expect(
        find.descendant(of: button, matching: find.text('Share')),
        findsOneWidget,
      );

      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(share.calls, hasLength(1));
      expect(share.calls.single.paths, fixture.outputs);
      _expectOrigin(tester, share.calls.single.origin, button);
    });

    testWidgets('shares every file of a batch at once', (tester) async {
      final fixture = await _ExportFixture.create(tester, count: 3);
      final share = _FakeShare();
      // The batch card's "Exporting selected..." label is wider than a
      // phone in the square test font while the batch runs.
      tester.platformDispatcher.textScaleFactorTestValue = .7;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await fixture.pumpEditor(tester, share);

      await tester.tap(find.byKey(const Key('export_commit')));
      await _settle(tester, rounds: 20);
      expect(find.textContaining('Batch export finished'), findsOneWidget);

      final button = find.byKey(const Key('share_exports'));
      expect(_tooltipOf(tester, button), 'Share all 3 exported files');
      expect(find.text('Share all 3'), findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(share.calls.single.paths, fixture.outputs);
    });

    testWidgets('hides Share where the device cannot share files', (
      tester,
    ) async {
      final fixture = await _ExportFixture.create(tester, count: 1);
      final share = _FakeShare(available: false);
      await fixture.pumpEditor(tester, share);

      await tester.tap(find.byKey(const Key('export_commit')));
      await _settle(tester);

      expect(find.textContaining('Export complete'), findsOneWidget);
      expect(find.byKey(const Key('share_exports')), findsNothing);
      expect(share.calls, isEmpty);
    });
  });

  group('movie export', () {
    testWidgets('offers Share once the movie is rendered', (tester) async {
      final share = _FakeShare();
      await _pumpTimeline(tester, share);

      expect(find.byKey(const Key('timeline_share_movie')), findsNothing);
      await tester.tap(find.byKey(const Key('timeline_render')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final button = find.byKey(const Key('timeline_share_movie'));
      expect(button, findsOneWidget);
      expect(_tooltipOf(tester, button), 'Share the movie');
      await tester.tap(button);
      await tester.pump();
      expect(share.calls.single.paths, [_RenderService.output]);
      _expectOrigin(tester, share.calls.single.origin, button);
    });

    testWidgets('has no Share button without a share sheet', (tester) async {
      await _pumpTimeline(tester, _FakeShare(available: false));
      await tester.tap(find.byKey(const Key('timeline_render')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Open exports'), findsOneWidget);
      expect(find.byKey(const Key('timeline_share_movie')), findsNothing);
    });
  });

  group('Local Exports', () {
    final items = [
      for (final name in ['a.jpg', 'b.jpg', 'c.mp4'])
        LocalExportItem(
          path: '/exports/$name',
          kind: name.endsWith('.mp4') ? MediaKind.video : MediaKind.photo,
          sizeBytes: 2048,
          modified: DateTime(2026, 5, 1),
        ),
    ];

    testWidgets('shares the selected exports together', (tester) async {
      _phoneViewport(tester);
      final share = _FakeShare();
      await tester.pumpWidget(
        CupertinoApp(
          home: ExportLibraryPage(
            service: _Library(items),
            shareService: share,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('local_export_selection_mode')));
      await tester.pump();
      final button = find.byKey(const Key('share_selected_local_exports'));
      expect(button, findsOneWidget);
      expect(tester.widget<CupertinoButton>(button).onPressed, isNull);

      await tester.tap(find.byKey(const Key('local_export_a.jpg')));
      await tester.tap(find.byKey(const Key('local_export_c.mp4')));
      await tester.pump();
      expect(find.text('Share 2'), findsOneWidget);
      expect(_tooltipOf(tester, button), 'Share the selected exports');

      final center = tester.getCenter(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump();
      expect(share.calls.single.paths, ['/exports/a.jpg', '/exports/c.mp4']);
      _expectOrigin(tester, share.calls.single.origin, button, at: center);
      // A finished share leaves selection mode, like Photos.
      expect(
        find.byKey(const Key('share_selected_local_exports')),
        findsNothing,
      );
    });

    testWidgets('shares one export from its detail page', (tester) async {
      _phoneViewport(tester);
      final share = _FakeShare();
      await tester.pumpWidget(
        CupertinoApp(
          home: ExportDetailPage(
            item: items.first,
            service: _Library(items),
            shareService: share,
          ),
        ),
      );
      await tester.pump();

      final button = find.byKey(const Key('share_local_export'));
      expect(button, findsOneWidget);
      expect(_tooltipOf(tester, button), 'Share export');
      expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      await tester.pump();
      expect(share.calls.single.paths, ['/exports/a.jpg']);
      _expectOrigin(tester, share.calls.single.origin, button);
    });

    testWidgets('shows only Delete without a share sheet', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(
        CupertinoApp(
          home: ExportLibraryPage(
            service: _Library(items),
            shareService: _FakeShare(available: false),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('local_export_selection_mode')));
      await tester.pump();
      expect(
        find.byKey(const Key('delete_selected_local_exports')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('share_selected_local_exports')),
        findsNothing,
      );
    });

    testWidgets('explains a failed share', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(
        CupertinoApp(
          home: ExportDetailPage(
            item: items.first,
            service: _Library(items),
            shareService: _FakeShare(error: StateError('File gone.')),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('share_local_export')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Could not share'), findsOneWidget);
      expect(find.text('File gone.'), findsOneWidget);
    });
  });
}

typedef _ShareCall = ({List<String> paths, Rect? origin});

class _FakeShare extends ShareService {
  _FakeShare({this.available = true, this.error});

  final bool available;
  final Object? error;
  final calls = <_ShareCall>[];

  @override
  bool get isAvailable => available;

  @override
  Future<ShareOutcome> shareFiles(
    List<String> paths, {
    required Rect? origin,
  }) async {
    calls.add((paths: List.of(paths), origin: origin));
    if (error case final error?) throw error;
    return ShareOutcome.shared;
  }
}

String? _tooltipOf(WidgetTester tester, Finder control) {
  final tooltip = find.ancestor(of: control, matching: find.byType(AppTooltip));
  if (tooltip.evaluate().isEmpty) return null;
  return tester.widget<AppTooltip>(tooltip.first).message;
}

/// The share popover must point at the tapped button.
void _expectOrigin(
  WidgetTester tester,
  Rect? origin,
  Finder button, {
  Offset? at,
}) {
  expect(origin, isNotNull);
  expect(origin!.isEmpty, isFalse);
  expect(origin.contains(at ?? tester.getCenter(button)), isTrue);
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _ExportFixture {
  _ExportFixture(this.inputs, this.outputs, this.imageService);

  final List<String> inputs;
  final List<String> outputs;
  final _FakeImageService imageService;

  static Future<_ExportFixture> create(
    WidgetTester tester, {
    required int count,
  }) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('aquarecover_share_'),
    ))!;
    addTearDown(() => directory.deleteSync(recursive: true));
    final inputs = [
      for (var i = 0; i < count; i++) '${directory.path}/dive$i.jpg',
    ];
    final outputs = [
      for (var i = 0; i < count; i++) '${directory.path}/dive$i restored.jpg',
    ];
    final jpeg = img.encodeJpg(img.Image(width: 16, height: 12));
    for (final path in [...inputs, ...outputs]) {
      File(path).writeAsBytesSync(jpeg);
    }
    return _ExportFixture(inputs, outputs, _FakeImageService(inputs, outputs));
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    ShareService share, {
    Size size = const Size(430, 1400),
  }) async {
    // Tall enough that the status card shows without scrolling.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CupertinoApp(
        home: EditorPage(
          initialPaths: inputs,
          reviewExportOnStart: true,
          inspectionService: const _PhotoInspection(),
          imageService: imageService,
          shareService: share,
        ),
      ),
    );
    await _settle(tester);
  }
}

class _FakeImageService extends ImageRestorationService {
  _FakeImageService(this.inputs, this.outputs);

  final List<String> inputs;
  final List<String> outputs;

  @override
  Future<String> restoreFile(
    String inputPath,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
    String? metadataSourcePath,
    ImageTransformSettings transform = const ImageTransformSettings(),
  }) async => outputs[inputs.indexOf(inputPath)];
}

class _PhotoInspection extends MediaInspectionService {
  const _PhotoInspection();

  @override
  Future<MediaMetadata> inspect(String path) async => MediaMetadata(
    path: path,
    fileName: File(path).uri.pathSegments.last,
    kind: MediaKind.photo,
    fileSizeBytes: 4,
    width: 16,
    height: 12,
  );
}

class _Library extends ExportLibraryService {
  const _Library(this.items);

  final List<LocalExportItem> items;

  @override
  Future<List<LocalExportItem>> load() async => [...items];
}

Future<void> _pumpTimeline(WidgetTester tester, ShareService share) async {
  _phoneViewport(tester);
  await tester.pumpWidget(
    CupertinoApp(
      home: TimelineEditorPage(
        store: _MemoryStore(),
        renderService: _RenderService(),
        exportDirectory: () async => Directory('/exports'),
        shareService: share,
        project: const TimelineProject(
          id: 'w',
          clips: [
            TimelineClip(
              id: 'a',
              path: '/m/a.jpg',
              kind: TimelineClipKind.image,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('timeline_open_export')));
  await tester.pump(const Duration(milliseconds: 300));
}

class _MemoryStore extends TimelineProjectStore {
  @override
  Future<void> save(TimelineProject project) async {}

  @override
  Future<List<TimelineProject>> list() async => const [];

  @override
  Future<void> delete(String id) async {}
}

class _RenderService extends TimelineRenderService {
  static const output = '/exports/Reef.mp4';

  @override
  TimelineRenderBackend get backend => TimelineRenderBackend.apple;

  @override
  Future<String> render(
    TimelineProject project, {
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async => output;
}
