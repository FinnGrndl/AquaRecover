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
import 'package:aqua_recover/features/library/export_library_page.dart';
import 'package:aqua_recover/features/logbook/logbook_media.dart';
import 'package:aqua_recover/features/logbook/logbook_page.dart';
import 'package:aqua_recover/features/onboarding/first_run_tutorial.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:aqua_recover/features/timeline/timeline_projects_page.dart';
import 'package:aqua_recover/l10n/app_localizations.dart';
import 'package:aqua_recover/l10n/app_localizations_de.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The key screens in German on an iPhone 15 sized window, at the default
/// text size and at large Dynamic Type: German strings show, and the longer
/// words do not overflow.
void main() {
  final de = AppLocalizationsDe();

  for (final textScale in [1.0, 2.0]) {
    group('German at text scale $textScale', () {
      testWidgets('start screen', (tester) async {
        _window(tester, textScale);
        await tester.pumpWidget(_german(const EditorPage()));
        await tester.pump();
        expect(find.text(de.startTagline), findsOneWidget);
        expect(find.text('Private, on-device restoration'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      for (final group in [
        EditorToolGroup.presets,
        EditorToolGroup.light,
        EditorToolGroup.color,
        EditorToolGroup.crop,
      ]) {
        testWidgets('photo editor, ${group.name}', (tester) async {
          _window(tester, textScale);
          await tester.pumpWidget(
            _german(
              EditorPage(
                initialPaths: const [_photo],
                initialToolGroup: group,
                inspectionService: const _Inspect(),
              ),
            ),
          );
          for (var i = 0; i < 7; i++) {
            await tester.pump();
          }
          expect(find.byKey(const Key('editor_review_export')), findsOneWidget);
          expect(find.text(de.toolPresets), findsWidgets);
          expect(find.text(de.toolCrop), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('movies, empty and with a movie', (tester) async {
        _window(tester, textScale);
        await tester.pumpWidget(
          _german(TimelineProjectsPage(store: _Store(const []))),
        );
        await tester.pump();
        expect(find.text(de.turnDiveIntoMovie), findsOneWidget);
        expect(find.text('Filme'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _german(
            TimelineProjectsPage(
              key: const Key('with_movie'),
              store: _Store(const [
                TimelineProject(id: 'p', name: 'Blue Corner, 11. Okt.'),
              ]),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(de.recent), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('movie editor with the title tools', (tester) async {
        _window(tester, textScale);
        await tester.pumpWidget(
          _german(const TimelineEditorPage(project: _movie)),
        );
        await tester.pump();
        expect(find.text(de.toolOverlay), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('timeline_overlay_title')));
        await tester.pump();
        if (find.byKey(const Key('timeline_text_field')).evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('timeline_tool_text')));
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(find.text(de.alignCenter), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('logbook', (tester) async {
        _window(tester, textScale);
        await tester.pumpWidget(
          _german(
            LogbookPage(
              store: _LogStore(_log),
              media: const _FakeMedia(),
              mapBuilder: (context, sites, onTap) => const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(de.logbook), findsWidgets);
        // German dates and decimals.
        expect(find.textContaining('18,4 m'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('local exports', (tester) async {
        _window(tester, textScale);
        await tester.pumpWidget(
          _german(
            ExportLibraryPage(
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
        expect(find.text(de.localExports), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('quick tour', (tester) async {
        _window(tester, textScale);
        await tester.pumpWidget(_german(const FirstRunTutorial()));
        await tester.pumpAndSettle();
        expect(find.text(de.skip), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (var page = 1; page < 4; page++) {
          await tester.tap(find.byKey(const Key('tutorial_next')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'page $page');
        }
      });
    });
  }
}

Widget _german(Widget home) => CupertinoApp(
  locale: const Locale('de'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void _window(WidgetTester tester, double textScale) {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

const _photo = 'docs/assets/demo-underwater-source.jpg';

const _movie = TimelineProject(
  id: 'p',
  clips: [TimelineClip(id: 'c', path: _photo, kind: TimelineClipKind.image)],
  overlays: [
    TimelineOverlay(
      id: 'title',
      kind: OverlayKind.text,
      lane: 0,
      stillSeconds: 4,
      title: TitleSpec(text: 'Blue Corner Wall'),
    ),
  ],
);

final _log = DiveLog(
  sites: const [
    DiveSite(id: 's1', name: 'Blue Hole', latitude: 28.57, longitude: 34.54),
  ],
  dives: [
    Dive(
      id: 'd1',
      number: 7,
      start: DateTime(2026, 5, 1, 10),
      siteId: 's1',
      maxDepth: 18.4,
      duration: const Duration(minutes: 45),
      waterTemperature: 24,
    ),
  ],
);

class _Inspect extends MediaInspectionService {
  const _Inspect();

  @override
  Future<MediaMetadata> inspect(String path) async => MediaMetadata(
    path: path,
    fileName: File(path).uri.pathSegments.last,
    kind: MediaKind.photo,
    fileSizeBytes: 2048,
    width: 1600,
    height: 1200,
  );
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

class _FakeMedia extends LogbookMedia {
  const _FakeMedia();

  @override
  Future<Uint8List?> thumbnail(DiveMedia media) async => null;
}
