import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/media_edit_state.dart';
import 'package:aqua_recover/core/models/media_job.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/features/timeline/movie_from_queue.dart';
import 'package:aqua_recover/features/timeline/timeline_controller.dart';
import 'package:aqua_recover/core/timeline/timeline_project_store.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:aqua_recover/features/timeline/timeline_projects_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps projects in memory and answers synchronously, so widget tests do
/// not wait on file I/O.
class _MemoryStore extends TimelineProjectStore {
  final projects = <String, TimelineProject>{};

  @override
  Future<void> save(TimelineProject project) {
    projects[project.id] = project;
    return Future.value();
  }

  @override
  Future<List<TimelineProject>> list() =>
      SynchronousFuture(projects.values.toList());

  @override
  Future<void> delete(String id) {
    projects.remove(id);
    return Future.value();
  }
}

TimelineController _controllerWith(List<String> paths) {
  final controller = TimelineController(const TimelineProject(id: 'p'));
  controller.addMedia(paths, videoDurations: {'/m/clip.mov': 10});
  return controller;
}

void main() {
  group('TimelineController', () {
    test('adds media after the selection with crossfades', () {
      final c = _controllerWith(['/m/a.jpg', '/m/clip.mov', '/m/notes.txt']);
      expect(c.project.clips.map((e) => e.kind), [
        TimelineClipKind.image,
        TimelineClipKind.video,
      ]);
      expect(c.project.clips.first.transition, ClipTransition.cut);
      expect(c.project.clips.last.transition, ClipTransition.crossfade);
      expect(c.project.clips.last.duration, 10);
      expect(c.selectedClip!.path, '/m/a.jpg');
    });

    test('reports skipped files', () {
      final c = TimelineController(const TimelineProject(id: 'p'));
      expect(c.addMedia(['/m/x.raw', '/m/y.doc']), ['/m/x.raw', '/m/y.doc']);
      expect(c.project.clips, isEmpty);
      expect(c.canUndo, isFalse);
    });

    test('split, undo, and redo', () {
      final c = _controllerWith(['/m/clip.mov']);
      c.seek(4);
      expect(c.splitAtPlayhead(), isTrue);
      expect(c.project.clips.map((e) => e.duration), [4, 6]);
      expect(c.selectedClip!.sourceStart, 4);
      c.undo();
      expect(c.project.clips.single.duration, 10);
      c.redo();
      expect(c.project.clips, hasLength(2));
    });

    test('trim start and end follow the playhead', () {
      final c = _controllerWith(['/m/clip.mov']);
      c.seek(2);
      expect(c.trimStartToPlayhead(), isTrue);
      expect(c.project.clips.single.sourceStart, 2);
      expect(c.playhead, 0);
      c.seek(5);
      expect(c.trimEndToPlayhead(), isTrue);
      expect(c.project.clips.single.sourceEnd, 7);
      expect(c.project.duration, 5);
    });

    test('reorder keeps the first clip a cut', () {
      final c = _controllerWith(['/m/a.jpg', '/m/b.jpg']);
      c.select(c.project.clips.last.id);
      c.moveSelected(-1);
      expect(c.project.clips.first.path, '/m/b.jpg');
      expect(c.project.clips.first.transition, ClipTransition.cut);
    });

    test('match grade copies grade and look to every clip', () {
      final c = _controllerWith(['/m/a.jpg', '/m/b.jpg', '/m/clip.mov']);
      c.setGrade(RestorationPreset.deep.settings);
      c.setLook(LutProfile.coralWarm);
      c.applyGradeToAll();
      for (final clip in c.project.clips) {
        expect(clip.grade.preset, RestorationPreset.deep);
        expect(clip.look.kind, LutKind.coralWarm);
      }
    });

    test('delete selects a neighbour', () {
      final c = _controllerWith(['/m/a.jpg', '/m/b.jpg']);
      c.deleteSelected();
      expect(c.project.clips.single.path, '/m/b.jpg');
      expect(c.project.clips.single.transition, ClipTransition.cut);
      expect(c.selectedClip!.path, '/m/b.jpg');
    });
  });

  test('movie from queue keeps per-item grades and skips RAW video', () {
    final project = movieFromQueue(
      const [
        MediaJob(id: 'a', inputPath: '/m/a.jpg', kind: MediaKind.photo),
        MediaJob(id: 'b', inputPath: '/m/b.raw', kind: MediaKind.rawVideo),
        MediaJob(id: 'c', inputPath: '/m/c.mov', kind: MediaKind.video),
      ],
      editStates: {
        'a': MediaEditState(
          settings: RestorationPreset.vivid.settings,
          lutProfile: LutProfile.blueWater,
        ),
      },
      videoDurations: const {'c': Duration(seconds: 8)},
      id: 'q',
    );
    expect(project.clips.map((c) => c.path), ['/m/a.jpg', '/m/c.mov']);
    expect(project.clips.first.grade.preset, RestorationPreset.vivid);
    expect(project.clips.first.look.kind, LutKind.blueWater);
    expect(project.clips.last.duration, 8);
    expect(project.clips.last.transition, ClipTransition.crossfade);
  });

  testWidgets('editor switches between Edit, Color, and Export', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CupertinoApp(
        home: TimelineEditorPage(project: TimelineProject(id: 'w')),
      ),
    );
    expect(find.text('Start with your best shots'), findsOneWidget);
    // Nothing to edit yet, so only the Add button in the viewer shows.
    expect(find.byKey(const Key('timeline_add')), findsNothing);
    expect(find.byKey(const Key('timeline_empty_add')), findsOneWidget);
  });

  testWidgets(
    'toolbar opens one panel at a time and the open tool collapses it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const CupertinoApp(
          home: TimelineEditorPage(
            project: TimelineProject(
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
      // The "+" at the end of the main track adds media.
      expect(find.byKey(const Key('timeline_add')), findsOneWidget);
      // Nothing is selected yet, so the root toolbar shows.
      expect(find.byKey(const Key('timeline_tool_format')), findsOneWidget);
      expect(find.byKey(const Key('timeline_split')), findsNothing);

      // Edit selects the clip under the playhead and swaps in its tools.
      await tester.tap(find.byKey(const Key('timeline_tool_edit')));
      await tester.pump();
      expect(find.byKey(const Key('timeline_split')), findsOneWidget);

      // The clip toolbar scrolls sideways on a phone.
      await tester.ensureVisible(find.byKey(const Key('timeline_tool_color')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('timeline_tool_color')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('timeline_grade_all')), findsOneWidget);

      // Tapping the open tool again collapses its panel.
      await tester.tap(find.byKey(const Key('timeline_tool_color')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('timeline_grade_all')), findsNothing);

      await tester.tap(find.byKey(const Key('timeline_open_export')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('1920 × 1080 · 00:03.0'), findsOneWidget);
      expect(find.text('Export movie'), findsOneWidget);

      // Done returns to the root toolbar.
      await tester.tap(find.byKey(const Key('timeline_tool_back')));
      await tester.pump();
      expect(find.byKey(const Key('timeline_split')), findsNothing);
    },
  );

  testWidgets('new movie starts from the picker, like iMovie', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    var picks = <String>[];
    await tester.pumpWidget(
      CupertinoApp(
        home: TimelineProjectsPage(
          store: store,
          mediaPicker: () async => picks,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Turn a dive into a movie'), findsOneWidget);

    // Cancelling the picker creates nothing.
    await tester.tap(find.byKey(const Key('timeline_new_movie_empty')));
    await tester.pumpAndSettle();
    expect(store.projects, isEmpty);
    expect(find.byType(TimelineEditorPage), findsNothing);

    picks = ['/m/a.jpg', '/m/b.jpg'];
    await tester.tap(find.byKey(const Key('timeline_new_movie')));
    // The photo preview keeps a spinner running, so pump instead of settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TimelineEditorPage), findsOneWidget);
    expect(find.text('2 items · 00:05 · Landscape 16:9'), findsOneWidget);
    expect(store.projects.values.single.name, startsWith('Dive, '));
  });

  test('default movie names read like a date', () {
    expect(
      TimelineProjectsPage.defaultName(DateTime(2026, 10, 11)),
      'Dive, Oct 11',
    );
  });
}
