import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/media_edit_state.dart';
import 'package:aqua_recover/core/models/media_job.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/features/timeline/movie_from_queue.dart';
import 'package:aqua_recover/features/timeline/timeline_controller.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('editor switches between Cut, Color, and Deliver', (
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
    expect(find.text('Add photos or clips to start a movie'), findsOneWidget);
    expect(find.byKey(const Key('timeline_add')), findsOneWidget);

    await tester.tap(find.byKey(const Key('timeline_page_color')));
    await tester.pump();
    expect(find.text('Select a clip to grade it.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timeline_page_deliver')));
    await tester.pump();
    expect(find.textContaining('1920 × 1080 · 00:00.0'), findsOneWidget);
  });
}
