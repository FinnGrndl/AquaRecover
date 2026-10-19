import 'dart:io';

import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/timeline/ffmpeg_timeline_renderer.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_project_store.dart';
import 'package:aqua_recover/core/timeline/timeline_render_service.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineClip _photo(String id, {double seconds = 3, ClipTransition? t}) =>
    TimelineClip(
      id: id,
      path: '/media/$id.jpg',
      kind: TimelineClipKind.image,
      stillSeconds: seconds,
      transition: t ?? ClipTransition.cut,
    );

TimelineClip _video(String id, double start, double end, {ClipTransition? t}) =>
    TimelineClip(
      id: id,
      path: '/media/$id.mov',
      kind: TimelineClipKind.video,
      sourceStart: start,
      sourceEnd: end,
      sourceDuration: 60,
      transition: t ?? ClipTransition.cut,
    );

void main() {
  group('layout', () {
    test('cuts butt clips together', () {
      final project = TimelineProject(
        id: 'p',
        clips: [_photo('a'), _video('b', 2, 6)],
      );
      final layout = project.layout;
      expect(layout.entries.map((e) => e.start), [0, 3]);
      expect(layout.duration, 7);
      expect(layout.entryAt(3.5)!.clip.id, 'b');
      expect(layout.entryAt(3.5)!.localTime(3.5), 0.5);
    });

    test('crossfades overlap by the transition, at most half a clip', () {
      final project = TimelineProject(
        id: 'p',
        transitionSeconds: 1,
        clips: [
          _photo('a'),
          _photo('b', seconds: 1, t: ClipTransition.crossfade),
          _photo('c', t: ClipTransition.crossfade),
        ],
      );
      final entries = project.layout.entries;
      expect(entries[1].overlapIn, 0.5);
      expect(entries[1].start, 2.5);
      expect(entries[2].overlapIn, 0.5);
      expect(entries[2].start, 3.0);
      expect(project.duration, 6.0);
    });

    test('output size keeps the aspect and even dimensions', () {
      expect(const TimelineProject(id: 'p').outputSize, (
        width: 1920,
        height: 1080,
      ));
      expect(
        const TimelineProject(
          id: 'p',
          aspect: TimelineAspect.portrait,
          quality: TimelineQuality.hd,
        ).outputSize,
        (width: 720, height: 1280),
      );
    });
  });

  group('clips', () {
    test('split a video at the playhead', () {
      final (left, right) = _video('v', 10, 20).splitAt(4, newId: 'w')!;
      expect((left.sourceStart, left.sourceEnd), (10, 14));
      expect((right.sourceStart, right.sourceEnd), (14, 20));
      expect(right.id, 'w');
    });

    test('refuse splits that leave a sliver', () {
      expect(_photo('p').splitAt(0.2, newId: 'x'), isNull);
      expect(_photo('p').splitAt(2.9, newId: 'x'), isNull);
    });

    test('round-trip through JSON', () {
      final project = TimelineProject(
        id: 'p',
        name: 'Blue Hole',
        aspect: TimelineAspect.square,
        clips: [
          _video('v', 1, 3).copyWith(
            look: LutProfile.blueWater,
            grade: RestorationPreset.deep.settings,
            muted: true,
          ),
          _photo('p').copyWith(motion: ClipMotion.zoomOut),
        ],
      );
      final restored = TimelineProject.fromJson(project.toJson());
      expect(restored.toJson(), project.toJson());
    });

    test('reject newer project formats', () {
      expect(
        () => TimelineProject.fromJson({'id': 'p', 'version': 99}),
        throwsFormatException,
      );
    });
  });

  test('ffmpeg graph grades, fits, and joins every clip', () {
    final project = TimelineProject(
      id: 'p',
      quality: TimelineQuality.hd,
      clips: [
        _photo('a').copyWith(motion: ClipMotion.zoomIn),
        _video('b', 2, 6, t: ClipTransition.crossfade),
        _photo('c'),
      ],
    );
    final args = FfmpegTimelineRenderer.buildArguments(project, const [
      ClipSourceInfo(hasAudio: false),
      ClipSourceInfo(hasAudio: true),
      ClipSourceInfo(hasAudio: false),
    ], outputPath: '/out/movie.mp4');
    final graph = args[args.indexOf('-filter_complex') + 1];
    expect(args, containsAllInOrder(['-loop', '1', '-i', '/media/a.jpg']));
    expect(args, containsAllInOrder(['-ss', '2.000', '-t', '4.000']));
    for (var i = 0; i < 3; i++) {
      expect(graph, contains('lut3d=file=clip$i.cube'));
    }
    expect(graph, contains('zoompan='));
    expect(
      graph,
      contains('xfade=transition=fade:duration=0.600:offset=2.400'),
    );
    expect(graph, contains('acrossfade=d=0.600'));
    expect(graph, contains('[1:a]aformat'));
    expect(graph, isNot(contains('[0:a]')));
    expect(graph, contains('[vx1][v2]concat=n=2:v=1:a=0[vx2]'));
    expect(args, containsAllInOrder(['-map', '[vx2]', '-map', '[ax2]']));
    expect(args.last, '/out/movie.mp4');
  });

  test('ffmpeg progress lines parse in microseconds', () {
    expect(
      FfmpegTimelineRenderer.parseProgressMicros('out_time_us=1500'),
      1500,
    );
    expect(FfmpegTimelineRenderer.parseProgressMicros('out_time_ms=42'), 42);
    expect(FfmpegTimelineRenderer.parseProgressMicros('fps=30'), isNull);
  });

  test('native arguments carry the layout so platforms agree on timing', () {
    final project = TimelineProject(
      id: 'p',
      clips: [
        _photo('a'),
        _photo('b', t: ClipTransition.crossfade),
      ],
    );
    final args = TimelineRenderService.nativeArguments(
      project,
      outputPath: '/out.mp4',
    );
    final clips = args['clips']! as List;
    expect((clips[1] as Map)['start'], closeTo(2.4, 1e-9));
    expect((clips[1] as Map)['overlapIn'], closeTo(0.6, 1e-9));
    expect(args['width'], 1920);
  });

  test('backends per platform', () {
    expect(
      TimelineRenderService.backendFor('ios'),
      TimelineRenderBackend.apple,
    );
    expect(
      TimelineRenderService.backendFor('android'),
      TimelineRenderBackend.android,
    );
    expect(
      TimelineRenderService.backendFor('windows', ffmpegAvailable: true),
      TimelineRenderBackend.ffmpeg,
    );
    expect(
      TimelineRenderService.backendFor('windows'),
      TimelineRenderBackend.none,
    );
  });

  test('store saves, lists, and deletes projects', () async {
    final dir = await Directory.systemTemp.createTemp('aq_tl_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = TimelineProjectStore(directory: () async => dir);
    await store.save(TimelineProject(id: 'one', clips: [_photo('a')]));
    await store.save(const TimelineProject(id: 'two', name: 'Second'));
    expect((await store.load('one'))!.clips.single.id, 'a');
    expect((await store.list()).map((p) => p.id), containsAll(['one', 'two']));
    await store.delete('one');
    expect(await store.load('one'), isNull);
    expect(() => store.load('../escape'), throwsArgumentError);
  });
}
