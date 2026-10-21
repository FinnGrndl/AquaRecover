import 'dart:io';

import 'package:aqua_recover/core/logbook/dive_log.dart';
import 'package:aqua_recover/core/logbook/dive_log_store.dart';
import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/persistence/export_library_service.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_project_store.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/core/models/raw_video_descriptor.dart';
import 'package:aqua_recover/features/editor/widgets/queue_overview_sheet.dart';
import 'package:aqua_recover/features/editor/widgets/raw_video_dialog.dart';
import 'package:aqua_recover/features/library/export_library_page.dart';
import 'package:aqua_recover/features/logbook/logbook_page.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:aqua_recover/features/timeline/timeline_projects_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout checks at the window sizes the app ships on: iPhone SE, large
/// Dynamic Type, iPad portrait and wide Mac and Windows windows.
void main() {
  testWidgets('the start screen keeps the brand readable on iPhone SE', (
    tester,
  ) async {
    _window(tester, const Size(320, 568));
    await tester.pumpWidget(const CupertinoApp(home: EditorPage()));
    await tester.pump();

    final subtitle = tester.getSize(
      find.text('Private, on-device restoration'),
    );
    expect(subtitle.width, greaterThan(150));
    // The shortcuts sit below the brand instead of beside it.
    expect(
      tester.getTopLeft(find.byKey(const Key('start_movies'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('start_brand_icon'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the start screen keeps the shortcuts beside the brand on a '
      'standard iPhone', (tester) async {
    _window(tester, const Size(390, 844));
    await tester.pumpWidget(const CupertinoApp(home: EditorPage()));
    await tester.pump();
    expect(
      tester.getCenter(find.byKey(const Key('start_movies'))).dy,
      moreOrLessEquals(
        tester.getCenter(find.byKey(const Key('start_brand_icon'))).dy,
        epsilon: 1,
      ),
    );
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('floating navigation bars fit at text scale $scale', (
      tester,
    ) async {
      _window(tester, const Size(320, 568), textScale: scale);
      await tester.pumpWidget(
        CupertinoApp(
          home: TimelineProjectsPage(
            store: _Store([
              const TimelineProject(id: 'p', name: 'Blue Corner, Oct 11'),
            ]),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Movies'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        CupertinoApp(
          home: EditorPage(
            initialPaths: const [_photo],
            initialToolGroup: EditorToolGroup.presets,
            inspectionService: const _Inspect(),
          ),
        ),
      );
      for (var i = 0; i < 7; i++) {
        await tester.pump();
      }
      expect(find.byKey(const Key('editor_review_export')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the video tool stops waiting when the frame preview cannot '
      'open the video', (tester) async {
    _window(tester, const Size(320, 568), textScale: 2);
    await tester.pumpWidget(
      CupertinoApp(
        home: EditorPage(
          initialPaths: const ['/clips/reef.mp4'],
          initialToolGroup: EditorToolGroup.video,
          inspectionService: const _Inspect(),
        ),
      ),
    );
    // There is no video_player implementation in widget tests, as on
    // Windows, so opening the video fails.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('video_preview_unavailable')), findsOneWidget);
    expect(find.text('Preparing video timeline…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom sheets keep a readable width in wide windows', (
    tester,
  ) async {
    _window(tester, const Size(1440, 900));
    await tester.pumpWidget(
      CupertinoApp(
        home: EditorPage(
          initialPaths: const [_photo, '$_photo?2'],
          inspectionService: const _Inspect(),
        ),
      ),
    );
    for (var i = 0; i < 7; i++) {
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('editor_open_queue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final sheet = tester.getRect(find.byType(QueueOverviewSheet));
    expect(sheet.width, lessThanOrEqualTo(640));
    expect(sheet.center.dx, moreOrLessEquals(720, epsilon: 1));
  });

  testWidgets('local exports use more columns in wide windows', (tester) async {
    _window(tester, const Size(1440, 900));
    await tester.pumpWidget(
      CupertinoApp(
        home: ExportLibraryPage(
          service: _Library([
            for (var i = 0; i < 8; i++)
              LocalExportItem(
                path: '/exports/reef_$i.mp4',
                kind: MediaKind.video,
                sizeBytes: 1000,
                modified: DateTime(2026, 5, i + 1),
              ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = tester.getSize(
      find.byKey(const Key('local_export_reef_0.mp4')),
    );
    expect(tile.width, lessThanOrEqualTo(220));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('local_export_selection_mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('local_export_select_all')));
    await tester.pumpAndSettle();
    final delete = tester.widget<CupertinoButton>(
      find.byKey(const Key('delete_selected_local_exports')),
    );
    // White on red, not the theme's blue.
    expect(delete.foregroundColor, CupertinoColors.white);
  });

  testWidgets('the title colors fit the side panel on iPad', (tester) async {
    _window(tester, const Size(820, 1180));
    await tester.pumpWidget(
      const CupertinoApp(
        home: TimelineEditorPage(
          project: TimelineProject(
            id: 'p',
            clips: [
              TimelineClip(id: 'c', path: _photo, kind: TimelineClipKind.image),
            ],
            overlays: [
              TimelineOverlay(
                id: 'title',
                kind: OverlayKind.text,
                lane: 0,
                stillSeconds: 4,
                title: TitleSpec(text: 'Blue Corner Wall'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('timeline_overlay_title')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('timeline_tool_text')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('timeline_text_field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(844, 390), const Size(568, 320)]) {
    testWidgets('the movie editor fits a landscape phone $size', (
      tester,
    ) async {
      _window(tester, size);
      await tester.pumpWidget(
        const CupertinoApp(
          home: TimelineEditorPage(
            project: TimelineProject(
              id: 'p',
              clips: [
                TimelineClip(
                  id: 'c',
                  path: _photo,
                  kind: TimelineClipKind.image,
                ),
              ],
              overlays: [
                TimelineOverlay(
                  id: 'title',
                  kind: OverlayKind.text,
                  lane: 0,
                  stillSeconds: 4,
                  title: TitleSpec(text: 'Blue Corner Wall'),
                ),
              ],
              audioClips: [
                TimelineAudioClip(
                  id: 'music',
                  path: '/m/a.m4a',
                  name: 'Blue Hour',
                  lane: 0,
                  sourceDuration: 40,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final toolbar = tester.getRect(
        find.byKey(const Key('timeline_tool_edit')),
      );
      expect(toolbar.bottom, lessThanOrEqualTo(size.height));
      expect(
        tester.getSize(find.byKey(const Key('timeline_viewer_canvas'))).height,
        greaterThan(40),
      );

      await tester.tap(find.byKey(const Key('timeline_open_export')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('timeline_render')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the movie editor fits above the keyboard on iPhone SE', (
    tester,
  ) async {
    _window(tester, const Size(320, 568));
    await tester.pumpWidget(
      const CupertinoApp(
        home: TimelineEditorPage(
          project: TimelineProject(
            id: 'p',
            clips: [
              TimelineClip(id: 'c', path: _photo, kind: TimelineClipKind.image),
            ],
            overlays: [
              TimelineOverlay(
                id: 'title',
                kind: OverlayKind.text,
                lane: 0,
                stillSeconds: 4,
                title: TitleSpec(text: 'Blue Corner Wall'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('timeline_overlay_title')));
    await tester.pump();
    if (find.byKey(const Key('timeline_text_field')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('timeline_tool_text')));
      await tester.pump(const Duration(milliseconds: 400));
    }
    // The keyboard comes up.
    tester.view.viewInsets = const FakeViewPadding(bottom: 253 * 2);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    final field = tester.getRect(find.byKey(const Key('timeline_text_field')));
    expect(field.bottom, lessThanOrEqualTo(568 - 253));
  });

  testWidgets('RAW pixel formats have 44 pt touch targets', (tester) async {
    _window(tester, const Size(320, 568));
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => RawVideoDialog.show(
              context,
              initial: RawVideoDescriptor.default4k,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final format in RawVideoDescriptor.commonPixelFormats) {
      final size = tester.getSize(
        find.ancestor(
          of: find.text(format),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(size.height, greaterThanOrEqualTo(44), reason: format);
      expect(size.width, greaterThanOrEqualTo(44), reason: format);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark screens draw plain labels light', (tester) async {
    _window(tester, const Size(390, 844));
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.light),
        home: LogbookPage(
          store: _LogStore(
            DiveLog(
              dives: [Dive(id: 'd', number: 1, start: DateTime(2026, 5, 1))],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['Dives', 'Map']) {
      final color = tester
          .renderObject<RenderParagraph>(find.text(label))
          .text
          .style!
          .color!;
      expect(color.computeLuminance(), greaterThan(.5), reason: label);
    }

    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.light),
        home: ExportLibraryPage(
          service: _Library([
            LocalExportItem(
              path: '/exports/reef.mp4',
              kind: MediaKind.video,
              sizeBytes: 1000,
              modified: DateTime(2026, 5, 1),
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final name = tester
        .renderObject<RenderParagraph>(find.text('reef.mp4'))
        .text
        .style!
        .color!;
    expect(name.computeLuminance(), greaterThan(.5));
  });
}

const _photo = 'docs/assets/demo-underwater-source.jpg';

void _window(WidgetTester tester, Size size, {double textScale = 1}) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

class _Inspect extends MediaInspectionService {
  const _Inspect();

  @override
  Future<MediaMetadata> inspect(String path) async {
    final video = path.endsWith('.mp4');
    return MediaMetadata(
      path: path,
      fileName: File(path).uri.pathSegments.last,
      kind: video ? MediaKind.video : MediaKind.photo,
      fileSizeBytes: 2048,
      width: 1600,
      height: 1200,
    );
  }
}

class _Store extends TimelineProjectStore {
  _Store(this.items);

  final List<TimelineProject> items;

  @override
  Future<void> save(TimelineProject project) async {}

  @override
  Future<List<TimelineProject>> list() => SynchronousFuture(items);

  @override
  Future<void> delete(String id) async {}
}

class _Library extends ExportLibraryService {
  const _Library(this.items);

  final List<LocalExportItem> items;

  @override
  Future<List<LocalExportItem>> load() async => items;
}

class _LogStore extends DiveLogStore {
  _LogStore(this.log);

  DiveLog log;

  @override
  Future<DiveLog> load() async => log;

  @override
  Future<void> save(DiveLog log) async => this.log = log;
}
