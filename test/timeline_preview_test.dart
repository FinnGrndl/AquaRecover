import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_render_plan.dart';
import 'package:aqua_recover/features/editor/widgets/gpu_preview_filter.dart';
import 'package:aqua_recover/features/timeline/preview/preview_audio.dart';
import 'package:aqua_recover/features/timeline/preview/preview_frame.dart';
import 'package:aqua_recover/features/timeline/preview/preview_math.dart';
import 'package:aqua_recover/features/timeline/preview/preview_player.dart';
import 'package:aqua_recover/features/timeline/preview/preview_scene.dart';
import 'package:aqua_recover/features/timeline/preview/preview_textures.dart';
import 'package:aqua_recover/features/timeline/preview/preview_video_pool.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A player that records what the preview asks of it. Seeks move its
/// position at once, as `video_player` does after a seek completes.
class FakePlayer implements PreviewPlayer {
  FakePlayer(this.path, {this.fail = false, this.holdSeeks = false});

  @override
  final String path;
  final bool fail;
  final bool holdSeeks;
  final calls = <String>[];
  final seeks = <double>[];
  final volumes = <double>[];
  final _held = <Completer<void>>[];
  bool initialized = false;
  bool disposed = false;
  bool playing = false;
  double speed = 1;

  @override
  Duration position = Duration.zero;

  @override
  Duration duration = const Duration(seconds: 20);

  @override
  Size size = const Size(1920, 1080);

  @override
  bool get isInitialized => initialized;

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    if (fail) throw StateError('cannot open $path');
    initialized = true;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> seekTo(Duration to) {
    calls.add('seek');
    seeks.add(to.inMicroseconds / 1e6);
    if (holdSeeks) {
      final done = Completer<void>();
      _held.add(done);
      return done.future.then((_) => position = to);
    }
    position = to;
    return Future.value();
  }

  /// Completes the oldest held seek.
  void releaseSeek() => _held.removeAt(0).complete();

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume');
    volumes.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    calls.add('speed');
    this.speed = speed;
  }

  @override
  Widget buildView() => SizedBox.expand(key: ValueKey('fake-view-$path'));

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class FakePlayers {
  FakePlayers({this.failing = const {}, this.holdSeeks = false});

  final Set<String> failing;
  final bool holdSeeks;
  final created = <FakePlayer>[];

  PreviewPlayer call(String path) {
    final player = FakePlayer(
      path,
      fail: failing.contains(path),
      holdSeeks: holdSeeks,
    );
    created.add(player);
    return player;
  }

  FakePlayer last(String path) => created.lastWhere((p) => p.path == path);
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Photo a (3 s), video b (source 1…5 s at 2×, crossfade, grain + mono,
/// fade out), a title and a photo overlay, and a music item.
TimelineProject sampleProject() => TimelineProject(
  id: 'p',
  clips: [
    const TimelineClip(
      id: 'a',
      path: '/m/a.jpg',
      kind: TimelineClipKind.image,
      stillSeconds: 3,
    ),
    TimelineClip(
      id: 'b',
      path: '/m/b.mov',
      kind: TimelineClipKind.video,
      sourceStart: 1,
      sourceEnd: 9,
      sourceDuration: 10,
      speed: 2,
      transition: ClipTransition.crossfade,
      fadeOut: 1,
      effects: [ClipEffect(EffectType.grain), ClipEffect(EffectType.mono)],
    ),
  ],
  overlays: [
    const TimelineOverlay(
      id: 'title',
      kind: OverlayKind.text,
      lane: 1,
      start: 0.5,
      stillSeconds: 2,
      centerY: 0.8,
      widthFraction: 0.45,
      mediaAspect: 5,
      animationIn: OverlayAnimation.pop,
      title: TitleSpec(text: 'Blue Hole'),
    ),
    const TimelineOverlay(
      id: 'photo',
      kind: OverlayKind.image,
      path: '/m/o.png',
      start: 1,
      stillSeconds: 3,
      centerX: 0.75,
      centerY: 0.3,
      widthFraction: 0.3,
      mediaAspect: 1.5,
    ),
  ],
  audioClips: const [
    TimelineAudioClip(
      id: 'music',
      path: '/m/music.m4a',
      sourceDuration: 120,
      volume: 0.7,
      fadeIn: 1,
      fadeOut: 2,
    ),
  ],
);

void main() {
  final plan = TimelineCompiler.compile(sampleProject());

  group('frame', () {
    test('lists the clips and layers active at t, bottom to top', () {
      // Clip b starts at 3 − 0.6 (crossfade) and lasts 4 s.
      final b = plan.clips.last;
      expect(b.start, closeTo(2.4, 1e-9));
      List<String> ids(double t) => [
        for (final l in PreviewFrame.at(plan, t).layers) l.layer.id,
      ];
      expect(ids(0.2), isEmpty);
      expect(ids(0.6), ['title']);
      // Overlays draw by lane: the photo (lane 0) under the title (lane 1).
      expect(ids(1.5), ['photo', 'title']);
      expect(ids(2.6), ['photo']);
      expect(ids(6.0), ['b.fadeOut']);

      final crossfade = PreviewFrame.at(plan, 2.7);
      expect([for (final c in crossfade.clips) c.clip.id], ['a', 'b']);
      expect(crossfade.clips.first.alpha, 1);
      expect(crossfade.clips.last.alpha, closeTo(0.3 / 0.6, 1e-9));
      // Source second of b: 1 + 0.3 s × 2.
      expect(crossfade.clips.last.sourceTime, closeTo(1.6, 1e-9));
    });

    test('the last instant keeps the fade-out on', () {
      final end = PreviewFrame.at(plan, plan.duration);
      expect(end.clips.single.clip.id, 'b');
      final fade = end.layer('b.fadeOut')!;
      expect(fade.key.opacity, closeTo(1, 1e-3));
    });

    test('key evaluation matches the engine', () {
      final swell = TimelineCompiler.compile(
        sampleProject().copyWith(
          clips: [
            TimelineClip(
              id: 's',
              path: '/m/s.jpg',
              kind: TimelineClipKind.image,
              stillSeconds: 4,
              effects: [
                ClipEffect(EffectType.swell),
                ClipEffect(EffectType.sunRays),
              ],
            ),
          ],
        ),
      );
      for (final p in [plan, swell]) {
        for (final layer in p.layers) {
          for (var u = -0.05; u <= layer.duration + 0.05; u += 0.037) {
            final mine = PreviewKeys.layerAt(layer.keys, u);
            final engine = TimelineRenderPlan.evaluateLayer(layer, u);
            expect(
              mine.toJson(),
              _close(engine.toJson()),
              reason: '${layer.id} at $u',
            );
          }
        }
        for (final clip in p.clips) {
          for (var u = 0.0; u <= clip.duration; u += 0.043) {
            expect(
              PreviewKeys.clipAt(clip.keys, u).toJson(),
              _close(TimelineRenderPlan.evaluateClip(clip, u).toJson()),
            );
          }
        }
      }
    });

    test('the plan compiles once per project, never per frame', () {
      final memo = PreviewPlanMemo();
      final project = sampleProject();
      final first = memo.resolve(project);
      for (var t = 0.0; t < 3; t += 1 / 60) {
        expect(identical(memo.resolve(project), first), isTrue);
      }
      expect(memo.compiles, 1);
      memo.resolve(project.copyWith(name: 'Renamed'));
      expect(memo.compiles, 2);
      // A plan handed in (the controller's cache) is used as is.
      final given = memo.resolve(project, plan: plan);
      expect(identical(given.plan, plan), isTrue);
      expect(memo.compiles, 2);
    });

    test('indexes sound and upcoming videos', () {
      final index = PreviewPlanIndex(plan);
      expect(index.trackAudio.single.id, 'music');
      expect(index.clipAudio.keys, ['b']);
      expect(
        [for (final v in index.videosStartingWithin(1.0, 1.5)) v.id],
        ['b'],
      );
      expect(index.videosStartingWithin(0, 1.5), isEmpty);
      // b fades in over the 0.6 s crossfade and out over 1 s.
      expect(index.videoGainAt('b', 2.7), closeTo(0.5, 1e-9));
      expect(index.videoGainAt('b', 4), 1);
      expect(index.videoGainAt('a', 1), 0);
    });

    test('a crossfade between two videos falls back to a hard switch', () {
      final frame = PreviewFrame(
        time: 0,
        clips: [
          PreviewClip(
            _videoClip('out'),
            localTime: 1,
            alpha: 1,
            transform: const TransformKey(t: 0),
          ),
          PreviewClip(
            _videoClip('in'),
            localTime: 0.2,
            alpha: 0.4,
            transform: const TransformKey(t: 0),
          ),
        ],
      );
      List<(String, double)> draw(Set<String> ready) => [
        for (final (c, a) in PreviewScene.mainClipsToDraw(
          frame.clips,
          ready.contains,
        ))
          (c.clip.id, a),
      ];
      expect(draw({'out', 'in'}), [('out', 1.0), ('in', 0.4)]);
      expect(draw({'in'}), [('in', 1.0)]);
      expect(draw({'out'}), [('out', 1.0)]);
      expect(draw({}), [('in', 1.0)]);
    });
  });

  group('geometry', () {
    test('clip transforms scale, rotate about the centre, then move', () {
      const view = Size(320, 180);
      const scale = 320 / 1920;
      const key = TransformKey(t: 0, scale: 1.2, x: 96, y: -48, rotation: 10);
      final m = PreviewGeometry.clipMatrix(key, view, scale);
      for (final p in const [
        Offset(0, 0),
        Offset(320, 180),
        Offset(40, 150),
        Offset(160, 90),
      ]) {
        final expected = PreviewGeometry.applyClipKey(key, view, scale, p);
        final actual = MatrixUtils.transformPoint(m, p);
        expect(actual.dx, closeTo(expected.dx, 1e-9));
        expect(actual.dy, closeTo(expected.dy, 1e-9));
      }
      // The centre only moves by the translation, in view units.
      final c = MatrixUtils.transformPoint(m, const Offset(160, 90));
      expect(c.dx, closeTo(160 + 16, 1e-9));
      expect(c.dy, closeTo(90 - 8, 1e-9));
      // Clockwise: a point right of the centre moves down.
      final right = MatrixUtils.transformPoint(
        PreviewGeometry.clipMatrix(
          const TransformKey(t: 0, rotation: 90),
          view,
          scale,
        ),
        const Offset(200, 90),
      );
      expect(right.dx, closeTo(160, 1e-9));
      expect(right.dy, closeTo(130, 1e-9));
    });

    test('layer rects scale from plan pixels to view points', () {
      const key = LayerKey(t: 0, x: 1152, y: 132, w: 576, h: 384, rotation: 30);
      expect(
        PreviewGeometry.layerRect(key, 1 / 3),
        const Rect.fromLTWH(384, 44, 192, 128),
      );
      expect(PreviewGeometry.layerRadians(key), closeTo(math.pi / 6, 1e-12));
      expect(PreviewGeometry.scaleFor(const Size(640, 360), 1920), 1 / 3);
    });

    test('frames fit contain or cover, centred', () {
      const canvas = Size(320, 180);
      expect(
        PreviewGeometry.fittedRect(
          const Size(1080, 1920),
          canvas,
          PlanFit.contain,
        ),
        Rect.fromCenter(
          center: const Offset(160, 90),
          width: 180 * 1080 / 1920,
          height: 180,
        ),
      );
      expect(
        PreviewGeometry.fittedRect(
          const Size(1080, 1920),
          canvas,
          PlanFit.cover,
        ),
        Rect.fromCenter(
          center: const Offset(160, 90),
          width: 320,
          height: 320 * 1920 / 1080,
        ),
      );
    });
  });

  group('colour', () {
    test('grade and effect matrices multiply into one filter', () {
      final grade = GpuPreviewFilter.matrixFor(const RestorationSettings());
      final effect = ColorMatrices.combine([
        ClipEffect(EffectType.sepia, intensity: 0.7),
      ])!;
      final both = PreviewColor.combine(gradeBytes: grade, effect: effect)!;
      for (final (r, g, b) in const [
        (10.0, 120.0, 200.0),
        (255.0, 0.0, 30.0),
        (90.0, 90.0, 90.0),
      ]) {
        final graded = ColorMatrices.apply(grade, r, g, b, 255);
        final sequential = ColorMatrices.apply(
          ColorMatrices.withByteOffsets(effect),
          graded[0],
          graded[1],
          graded[2],
          graded[3],
        );
        final once = ColorMatrices.apply(both, r, g, b, 255);
        for (var i = 0; i < 4; i++) {
          expect(once[i], closeTo(sequential[i], 1e-6));
        }
      }
      expect(PreviewColor.combine(gradeBytes: grade), same(grade));
      expect(
        PreviewColor.combine(effect: effect),
        ColorMatrices.withByteOffsets(effect),
      );
      expect(PreviewColor.combine(), isNull);
    });
  });

  group('audio maths', () {
    const segment = PlanAudio(
      id: 'm',
      path: '/m.m4a',
      origin: PlanAudioOrigin.track,
      start: 2,
      sourceStart: 0,
      sourceDuration: 10,
      speed: 1,
      volume: 0.8,
      fadeIn: 1,
      fadeOut: 2,
    );

    test('gain is volume × fade', () {
      expect(PreviewAudioMath.gainAt(segment, 1.9), 0);
      expect(PreviewAudioMath.gainAt(segment, 2), 0);
      expect(PreviewAudioMath.gainAt(segment, 2.5), closeTo(0.4, 1e-9));
      expect(PreviewAudioMath.gainAt(segment, 6), closeTo(0.8, 1e-9));
      expect(PreviewAudioMath.gainAt(segment, 11), closeTo(0.4, 1e-9));
      expect(PreviewAudioMath.gainAt(segment, 12), 0);
    });

    test('volume calls are throttled but fades end exactly', () {
      bool should(double? current, double next, double lastAt, double now) =>
          PreviewAudioMath.shouldSetVolume(
            current: current,
            next: next,
            lastSetAt: lastAt,
            now: now,
          );
      expect(should(null, 0.5, 0, 0), isTrue);
      expect(should(0.5, 0.5, 0, 1), isFalse);
      expect(should(0.5, 0.51, 0, 1), isFalse);
      expect(should(0.5, 0.6, 1, 1.03), isFalse);
      expect(should(0.5, 0.6, 1, 1.1), isTrue);
      expect(should(0.05, 0, 1, 1.01), isTrue);
    });
  });

  group('grain', () {
    test('a new deterministic pattern every movie frame', () {
      final a = PreviewGrainMath.offsetFor(1.0, 30, 256);
      expect(PreviewGrainMath.offsetFor(1.01, 30, 256), a);
      final b = PreviewGrainMath.offsetFor(1.04, 30, 256);
      expect(b, isNot(a));
      for (var t = 0.0; t < 5; t += 0.1) {
        final o = PreviewGrainMath.offsetFor(t, 30, 256);
        expect(o.dx, inInclusiveRange(0, 255));
        expect(o.dy, inInclusiveRange(0, 255));
      }
      expect(PreviewGrainMath.opacityFor(0.018, 0.18), closeTo(0.1, 1e-9));
      expect(PreviewGrainMath.opacityFor(1, 0.18), 1);
    });
  });

  group('video pool', () {
    late FakePlayers players;
    late double now;
    PreviewVideoPool pool({int maxDecoding = 2, int maxPlayers = 3}) =>
        PreviewVideoPool(
          create: players.call,
          maxDecoding: maxDecoding,
          maxPlayers: maxPlayers,
          clock: () => now,
        );

    setUp(() {
      players = FakePlayers(failing: {'/bad.mov'});
      now = 0;
    });

    VideoRequest req(
      String id, {
      double at = 0,
      bool visible = true,
      String? path,
    }) => VideoRequest(
      id: id,
      path: path ?? '/$id.mov',
      sourceTime: at,
      visible: visible,
    );

    test('shows at most two decoding videos; the rest get posters', () async {
      final p = pool();
      p.update([req('a'), req('b'), req('c')], playing: false);
      expect(p.liveIds, ['a', 'b']);
      expect(p.isOpening('a'), isTrue);
      expect(p.playerFor('a'), isNull);
      await settle();
      expect(p.playerFor('a'), isNotNull);
      expect(p.playerFor('c'), isNull);
      p.update([req('a', at: 2), req('b'), req('c')], playing: false);
      expect(players.last('/a.mov').seeks, [2]);
      expect(p.isShowing('c'), isFalse);
    });

    test('prepares upcoming videos only while playing', () async {
      final p = pool();
      p.update([req('a'), req('next', at: 4, visible: false)], playing: false);
      expect(p.liveIds, ['a']);
      p.update([req('a'), req('next', at: 4, visible: false)], playing: true);
      expect(p.liveIds, ['a', 'next']);
      await settle();
      p.update([req('a'), req('next', at: 4, visible: false)], playing: true);
      final next = players.last('/next.mov');
      expect(next.seeks, [4]);
      expect(next.calls, isNot(contains('play')));
      expect(p.isShowing('next'), isFalse);
      // Parked once, not re-sought every frame.
      p.update([req('a'), req('next', at: 4, visible: false)], playing: true);
      expect(next.seeks, [4]);
    });

    test('evicts the least recently used idle player at the cap', () async {
      final p = pool();
      for (final id in ['a', 'b', 'c']) {
        now += 1;
        p.update([req(id)], playing: false);
        await settle();
      }
      expect(p.liveIds, unorderedEquals(['a', 'b', 'c']));
      now += 1;
      p.update([req('d')], playing: false);
      expect(p.liveIds, unorderedEquals(['b', 'c', 'd']));
      expect(players.last('/a.mov').disposed, isTrue);
      expect(players.last('/b.mov').disposed, isFalse);
      // Upcoming items never push out a visible one.
      now += 1;
      p.update([
        req('b'),
        req('c'),
        req('d'),
        req('e', visible: false),
      ], playing: true);
      expect(p.liveIds, unorderedEquals(['b', 'c', 'd']));
      p.dispose();
      expect(players.created.where((x) => !x.disposed), isEmpty);
    });

    test('an idle player of the same file is reused', () async {
      final p = pool();
      p.update([req('left', path: '/same.mov')], playing: false);
      await settle();
      p.update([req('right', path: '/same.mov', at: 3)], playing: false);
      expect(players.created, hasLength(1));
      expect(p.playerFor('right'), same(players.created.single));
      expect(players.created.single.seeks.last, 3);
    });

    test('a file that cannot open is not retried', () async {
      String? failed;
      final p = PreviewVideoPool(
        create: players.call,
        clock: () => now,
        onOpened: (id, player) {
          if (player == null) failed = id;
        },
      );
      p.update([req('x', path: '/bad.mov')], playing: false);
      await settle();
      expect(failed, 'x');
      expect(p.liveIds, isEmpty);
      p.update([req('x', path: '/bad.mov')], playing: false);
      expect(players.created, hasLength(1));
    });

    test('scrubbing seeks coalesce to the newest position', () async {
      players = FakePlayers(holdSeeks: true);
      final p = pool();
      p.update([req('a', at: 1)], playing: false);
      await settle();
      p.update([req('a', at: 1)], playing: false);
      p.update([req('a', at: 2)], playing: false);
      p.update([req('a', at: 3)], playing: false);
      final a = players.last('/a.mov');
      expect(a.seeks, [1]);
      a.releaseSeek();
      await settle();
      expect(a.seeks, [1, 3]);
      a.releaseSeek();
      await settle();
      expect(a.seeks, [1, 3]);
    });

    test('playback seeks only when it drifts more than 0.1 s', () async {
      final p = pool();
      VideoRequest playReq(double at) => VideoRequest(
        id: 'a',
        path: '/a.mov',
        sourceTime: at,
        speed: 2,
        volume: 0.5,
      );
      p.update([playReq(1)], playing: true);
      await settle();
      p.update([playReq(1)], playing: true);
      await settle();
      final a = players.last('/a.mov');
      expect(a.calls, containsAllInOrder(['speed', 'volume', 'seek', 'play']));
      expect(a.speed, 2);
      expect(a.volumes, [0.5]);
      expect(a.seeks, [1]);
      // Half a second later at 2×: the player reports where it should be.
      now = 0.5;
      a.position = const Duration(milliseconds: 2000);
      p.update([playReq(2.05)], playing: true);
      expect(a.seeks, [1]);
      // It fell behind by 0.4 s.
      now = 1.0;
      a.position = const Duration(milliseconds: 2600);
      p.update([playReq(3.0)], playing: true);
      expect(a.seeks, [1, 3.0]);
      await settle();
      // Pausing stops it and shows the exact frame.
      p.update([playReq(3.1)], playing: false);
      expect(a.calls.last, 'seek');
      expect(a.playing, isFalse);
    });
  });

  group('audio mixer', () {
    late FakePlayers players;
    late double now;
    final music = plan.audio.firstWhere((a) => a.id == 'music');

    setUp(() {
      players = FakePlayers();
      now = 0;
    });

    test('plays audio items with the playhead, faded', () async {
      final mixer = PreviewAudioMixer(create: players.call, clock: () => now);
      mixer.update([music], 0.5, playing: false);
      expect(players.created, isEmpty);
      mixer.update([music], 0.5, playing: true);
      await settle();
      mixer.update([music], 0.5, playing: true);
      final player = players.single();
      expect(player.seeks, [0.5]);
      expect(player.playing, isTrue);
      expect(player.volumes.last, closeTo(0.35, 1e-9));
      mixer.update([music], 0.6, playing: false);
      expect(player.playing, isFalse);
      mixer.dispose();
      expect(player.disposed, isTrue);
    });

    test('prepares items that start soon and skips when disabled', () async {
      final later = PlanAudio(
        id: 'later',
        path: '/later.m4a',
        origin: PlanAudioOrigin.track,
        start: 5,
        sourceStart: 2,
        sourceDuration: 3,
        speed: 1,
        volume: 1,
        fadeIn: 0,
        fadeOut: 0,
      );
      final mixer = PreviewAudioMixer(create: players.call, clock: () => now);
      mixer.update([later], 3, playing: true);
      expect(players.created, isEmpty);
      mixer.update([later], 4, playing: true);
      await settle();
      mixer.update([later], 4.1, playing: true);
      expect(players.single().seeks, [2]);
      expect(players.single().playing, isFalse);

      final off = PreviewAudioMixer(create: players.call, enabled: false);
      off.update([later], 5.5, playing: true);
      expect(players.created, hasLength(1));
    });
  });

  group('textures', () {
    test('view-size specs', () {
      final title = plan.layers.firstWhere((l) => l.id == 'title');
      final spec = (title.source as GeneratedSource).spec as TitleTexture;
      final scaled =
          PreviewTextureSizing.specFor(title, spec, 0.5) as TitleTexture;
      expect(scaled.width, (spec.width * 0.5).round());
      expect(scaled.canvasHeight, spec.canvasHeight);

      const rays = PlanLayer(
        id: 'r',
        kind: PlanLayerKind.image,
        source: GeneratedSource(
          EffectTexture(EffectType.sunRays, 1, 1280, 720),
        ),
        start: 0,
        duration: 1,
        keys: [LayerKey(t: 0, x: -288, y: -162, w: 2496, h: 1404)],
      );
      final small =
          PreviewTextureSizing.specFor(
                rays,
                (rays.source as GeneratedSource).spec,
                1,
              )
              as EffectTexture;
      expect(small.width, PreviewTextureSizing.maxSoftSide);
      expect(small.height, 288);
    });

    test('rasterises once, hands out handles, evicts by bytes', () async {
      final made = <GeneratedSpec>[];
      Future<ui.Image> raster(GeneratedSpec spec) {
        made.add(spec);
        return _image(10, 10);
      }

      final cache = PreviewTextureCache(rasterize: raster, maxBytes: 1000);
      const a = EffectTexture(EffectType.vignette, 1, 10, 10);
      const b = EffectTexture(EffectType.vignette, 0.5, 10, 10);
      final first = cache.load('a', a);
      final second = cache.load('a', a);
      final ia = (await first)!, ib = (await second)!;
      expect(made, hasLength(1));
      expect(ia.isCloneOf(ib), isTrue);
      expect(cache.keys, ['a']);

      final held = cache.acquire('a')!;
      final other = (await cache.load('b', b))!;
      // 2 × 400 bytes > 1000? No: both fit. A third evicts the oldest.
      expect(cache.keys, ['a', 'b']);
      await cache.load(
        'c',
        const EffectTexture(EffectType.vignette, 0.2, 10, 10),
      );
      expect(cache.keys, ['b', 'c']);
      // The handle given out survives eviction.
      expect(held.debugDisposed, isFalse);
      for (final image in [ia, ib, held, other]) {
        image.dispose();
      }
      cache.dispose();
      expect(cache.bytes, 0);
    });
  });
}

extension on FakePlayers {
  FakePlayer single() => created.single;
}

PlanClip _videoClip(String id) => PlanClip(
  id: id,
  path: '/$id.mov',
  kind: TimelineClipKind.video,
  start: 0,
  duration: 2,
  overlapIn: 0,
  sourceStart: 0,
  sourceDuration: 2,
  speed: 1,
  fit: PlanFit.contain,
  keys: const [],
  grade: const RestorationSettings(),
  look: LutProfile.none,
  filters: PlanFilters.none,
);

Future<ui.Image> _image(int w, int h) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(w, h);
}

Matcher _close(Map<String, Object?> expected) =>
    predicate<Map<String, Object?>>(
      (actual) => expected.entries.every((e) {
        final a = actual[e.key] as double, b = e.value as double;
        return (a - b).abs() < 1e-6;
      }),
      'close to $expected',
    );
