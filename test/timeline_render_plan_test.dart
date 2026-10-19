import 'dart:math' as math;

import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_render_plan.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineClip _video(
  String id,
  double start,
  double end, {
  double speed = 1,
  ClipTransition transition = ClipTransition.cut,
  List<ClipEffect> effects = const [],
}) => TimelineClip(
  id: id,
  path: '/media/$id.mov',
  kind: TimelineClipKind.video,
  sourceStart: start,
  sourceEnd: end,
  sourceDuration: 60,
  speed: speed,
  transition: transition,
  effects: effects,
);

TimelineClip _photo(
  String id, {
  double seconds = 4,
  ClipTransition transition = ClipTransition.cut,
  List<ClipEffect> effects = const [],
}) => TimelineClip(
  id: id,
  path: '/media/$id.jpg',
  kind: TimelineClipKind.image,
  stillSeconds: seconds,
  transition: transition,
  effects: effects,
);

TimelineOverlay _image(
  String id, {
  int lane = 0,
  double start = 0,
  double seconds = 3,
}) => TimelineOverlay(
  id: id,
  kind: OverlayKind.image,
  path: '/media/$id.png',
  lane: lane,
  start: start,
  stillSeconds: seconds,
  centerX: 0.25,
  centerY: 0.75,
  widthFraction: 0.5,
  mediaAspect: 2,
);

TimelineRenderPlan _compile(
  List<TimelineClip> clips, {
  List<TimelineOverlay> overlays = const [],
  List<TimelineAudioClip> audio = const [],
  double transitionSeconds = 0.6,
  TimelineQuality quality = TimelineQuality.fullHd,
  TitleAspectResolver? titleAspect,
}) => TimelineCompiler.compile(
  TimelineProject(
    id: 'p',
    clips: clips,
    overlays: overlays,
    audioClips: audio,
    transitionSeconds: transitionSeconds,
    quality: quality,
  ),
  titleAspect: titleAspect,
);

PlanLayer _layer(TimelineRenderPlan plan, String id) =>
    plan.layers.singleWhere((layer) => layer.id == id);

List<double> _times(List<LayerKey> keys) => [for (final k in keys) k.t];

List<double> _opacities(List<LayerKey> keys) => [
  for (final k in keys) k.opacity,
];

Matcher _closeToList(List<double> expected, [double tolerance = 1e-9]) =>
    pairwiseCompare<double, double>(
      expected,
      (a, b) => (a - b).abs() <= tolerance,
      'within $tolerance of',
    );

void main() {
  group('main clips', () {
    test('carry absolute timing and source ranges', () {
      final plan = _compile([
        _video('a', 10, 20, speed: 2),
        _photo('b', seconds: 3, transition: ClipTransition.crossfade),
      ], transitionSeconds: 0.5);
      expect((plan.width, plan.height, plan.frameRate), (1920, 1080, 30));
      expect(plan.duration, 7.5);
      final a = plan.clips[0], b = plan.clips[1];
      expect((a.start, a.duration, a.overlapIn), (0, 5, 0));
      expect((a.sourceStart, a.sourceDuration, a.speed), (10, 10, 2));
      expect(a.fit, PlanFit.contain);
      expect(a.keys, isEmpty);
      expect(b.kind, TimelineClipKind.image);
      expect((b.start, b.duration, b.overlapIn), (4.5, 3, 0.5));
      expect((b.sourceStart, b.sourceDuration, b.speed), (0, 3, 1));
    });

    test('photo zoom compiles to two cover keys', () {
      final plan = _compile([
        _photo('in').copyWith(motion: ClipMotion.zoomIn),
        _photo('out').copyWith(motion: ClipMotion.zoomOut),
      ]);
      final zoomIn = plan.clips[0], zoomOut = plan.clips[1];
      expect(zoomIn.fit, PlanFit.cover);
      expect(
        [for (final k in zoomIn.keys) (k.t, k.scale)],
        [(0, 1), (4, 1.15)],
      );
      expect(
        [for (final k in zoomOut.keys) (k.t, k.scale)],
        [(0, 1.15), (4, 1)],
      );
      expect(
        TimelineRenderPlan.evaluateClip(zoomIn, 2).scale,
        closeTo(1.075, 1e-12),
      );
    });

    test('videos ignore photo motion but drift moves them', () {
      final still = _compile([
        _video('v', 0, 6).copyWith(motion: ClipMotion.zoomIn),
      ]).clips.single;
      expect(still.keys, isEmpty);
      expect(still.fit, PlanFit.contain);

      final drift = _compile([
        _video('v', 0, 6, effects: [ClipEffect(EffectType.drift)]),
      ]).clips.single;
      expect(drift.fit, PlanFit.cover);
      expect(drift.keys, hasLength(2));
      expect(drift.keys.last.t, 6);
      expect(drift.keys.last.scale, closeTo(1.09, 1e-12));
      expect(drift.keys.last.x, closeTo(-0.04 * 1920 * 0.5, 1e-9));
      expect(drift.keys.first.isIdentity, isTrue);
    });

    test('swell samples every 0.1 s with a zoom that hides the edges', () {
      final clip = _compile([
        _video(
          'v',
          0,
          2,
          effects: [ClipEffect(EffectType.swell, intensity: 1)],
        ),
      ]).clips.single;
      expect(clip.fit, PlanFit.cover);
      expect(clip.keys, hasLength(21));
      expect(clip.keys[5].t, closeTo(0.5, 1e-12));
      final scale = TimelineCompiler.swellScale(1, 1920, 1080);
      expect(scale, greaterThanOrEqualTo(1.05));
      // Rotation and drift peaks need more than the nominal 5 %.
      expect(scale, closeTo(1.0676, 1e-3));
      for (final key in clip.keys) {
        expect(key.scale, scale);
      }
      final k = clip.keys[5];
      expect(k.rotation, closeTo(1.5 * math.sin(2 * math.pi * 0.5 / 5), 1e-9));
      expect(
        k.x,
        closeTo(0.015 * 1920 * math.sin(1.6 * math.pi * 0.5 / 5 + 0.7), 1e-9),
      );
      expect(
        k.y,
        closeTo(0.01 * 1080 * math.sin(2.6 * math.pi * 0.5 / 5), 1e-9),
      );
      expect(
        TimelineCompiler.swellScale(0.4, 1920, 1080),
        greaterThanOrEqualTo(1.02),
      );
    });

    test('combined motions multiply scales on a sampled curve', () {
      final clip = _compile([
        _photo(
          'p',
          seconds: 2,
          effects: [ClipEffect(EffectType.drift, intensity: 1)],
        ).copyWith(motion: ClipMotion.zoomIn),
      ]).clips.single;
      expect(clip.keys, hasLength(21));
      final mid = clip.keys[10];
      expect(mid.scale, closeTo((1 + 0.15 * 0.5) * (1 + 0.18 * 0.5), 1e-12));
      expect(mid.x, closeTo(-0.04 * 1920 * 0.5, 1e-9));
    });

    test('filters resolve in output pixels', () {
      final effects = [
        ClipEffect(EffectType.mono, intensity: 0.7),
        ClipEffect(EffectType.softFocus, intensity: 0.5),
        ClipEffect(EffectType.clarity, intensity: 0.4),
        ClipEffect(EffectType.grain, intensity: 0.3),
        ClipEffect(EffectType.sepia, intensity: 0.5),
      ];
      final hd = _compile([_photo('p', effects: effects)]).clips.single;
      expect(
        hd.filters.colorMatrix,
        _closeToList(ColorMatrices.combine(effects)!),
      );
      expect(hd.filters.blurSigma, closeTo(3, 1e-12));
      expect(hd.filters.sharpen, closeTo(0.4, 1e-12));
      expect(hd.filters.sharpenSigma, closeTo(2, 1e-12));
      expect(hd.filters.grain, closeTo(0.018, 1e-12));
      final uhd = _compile([
        _photo('p', effects: effects),
      ], quality: TimelineQuality.uhd).clips.single;
      expect(uhd.filters.blurSigma, closeTo(6, 1e-12));
      expect(uhd.filters.sharpenSigma, closeTo(4, 1e-12));
      final plain = _compile([_photo('p')]).clips.single.filters;
      expect(plain.isEmpty, isTrue);
      expect(plain.colorMatrix, isNull);
    });
  });

  group('layers', () {
    test(
      'draw in spec order: clip layers, then overlays by lane and start',
      () {
        final plan = _compile(
          [
            _photo(
              'A',
              effects: [
                ClipEffect(EffectType.caustics),
                ClipEffect(EffectType.vignette),
                ClipEffect(EffectType.strobe),
                ClipEffect(EffectType.grain),
                ClipEffect(EffectType.swell),
              ],
            ).copyWith(fadeIn: 1, fadeOut: 1),
            _photo('B', transition: ClipTransition.dipBlack),
          ],
          overlays: [
            _image('o1', lane: 1, start: 0),
            _image('o2', lane: 0, start: 2),
            _image('o3', lane: 0, start: 1),
          ],
        );
        expect(plan.layers.map((l) => l.id), [
          'A.fx0-caustics',
          'A.fx1-vignette',
          'A.fx2-strobe',
          'A.fadeIn',
          'A.fadeOut',
          'B.dip',
          'o3',
          'o2',
          'o1',
        ]);
        expect(plan.layers.take(6).map((l) => l.ownerClipId), [
          'A',
          'A',
          'A',
          'A',
          'A',
          'B',
        ]);
        expect(plan.layers.last.ownerClipId, isNull);
      },
    );

    test('fades are colour layers ramping over the clip ends', () {
      final plan = _compile([
        _photo(
          'A',
        ).copyWith(fadeIn: 1, fadeOut: 1.5, fadeColor: FadeColor.deepBlue),
      ]);
      final fadeIn = _layer(plan, 'A.fadeIn');
      expect(fadeIn.kind, PlanLayerKind.color);
      expect(fadeIn.source, const ColorSource(0xFF06263F));
      expect((fadeIn.start, fadeIn.duration), (0, 1));
      expect(_times(fadeIn.keys), [0, 1]);
      expect(_opacities(fadeIn.keys), [1, 0]);
      final k = fadeIn.keys.first;
      expect((k.x, k.y, k.w, k.h, k.rotation), (0, 0, 1920, 1080, 0));
      final fadeOut = _layer(plan, 'A.fadeOut');
      expect((fadeOut.start, fadeOut.duration), (2.5, 1.5));
      expect(_opacities(fadeOut.keys), [0, 1]);
      expect(
        TimelineRenderPlan.evaluateLayer(fadeOut, 0.75).opacity,
        closeTo(0.5, 1e-12),
      );
    });

    test('dips straddle the cut, clamped to half of each neighbour', () {
      final plan = _compile([
        _photo('A'),
        _photo('B', transition: ClipTransition.dipBlack),
        _photo('C', seconds: 1, transition: ClipTransition.dipWhite),
      ]);
      final black = _layer(plan, 'B.dip');
      expect(black.source, const ColorSource(0xFF000000));
      expect((black.start, black.duration), (3.7, 0.6));
      expect(_times(black.keys), _closeToList([0, 0.3, 0.6]));
      expect(_opacities(black.keys), [0, 1, 0]);
      final white = _layer(plan, 'C.dip');
      expect(white.source, const ColorSource(0xFFFFFFFF));
      expect((white.start, white.duration), (7.75, 0.5));
      expect(plan.clips.map((c) => c.overlapIn), [0, 0, 0]);
    });

    test('strobe flashes white for 0.3 s at the clip start', () {
      final plan = _compile([
        _photo('A'),
        _photo('B', effects: [ClipEffect(EffectType.strobe)]),
      ]);
      final strobe = _layer(plan, 'B.fx0-strobe');
      expect(strobe.source, const ColorSource(0xFFFFFFFF));
      expect((strobe.start, strobe.duration), (4, 0.3));
      expect(_times(strobe.keys), [0, 0.3]);
      expect(_opacities(strobe.keys), _closeToList([0.7, 0]));
    });

    test('static textures fill the canvas with one key', () {
      final plan = _compile([
        _photo(
          'A',
          effects: [
            ClipEffect(EffectType.vignette),
            ClipEffect(EffectType.cinemaBars, intensity: 0.5),
            ClipEffect(EffectType.vignette, intensity: 0),
          ],
        ),
      ]);
      final vignette = _layer(plan, 'A.fx0-vignette');
      expect(vignette.kind, PlanLayerKind.image);
      expect(
        vignette.source,
        const GeneratedSource(
          EffectTexture(EffectType.vignette, 0.5, 1920, 1080),
        ),
      );
      expect((vignette.start, vignette.duration), (0, 4));
      expect(vignette.keys, hasLength(1));
      final k = vignette.keys.single;
      expect((k.t, k.x, k.y, k.w, k.h, k.opacity), (0, 0, 0, 1920, 1080, 1));
      expect(
        _layer(plan, 'A.fx1-cinemaBars').source,
        const GeneratedSource(
          EffectTexture(EffectType.cinemaBars, 0.5, 1920, 1080),
        ),
      );
      // Zero intensity adds nothing.
      expect(plan.layers, hasLength(2));
    });

    test('clip layers dissolve with their clip across crossfades', () {
      final plan = _compile([
        _photo(
          'A',
          effects: [ClipEffect(EffectType.vignette)],
        ).copyWith(fadeOut: 1),
        _photo(
          'B',
          transition: ClipTransition.crossfade,
          effects: [ClipEffect(EffectType.vignette)],
        ),
      ], transitionSeconds: 1);
      final a = _layer(plan, 'A.fx0-vignette');
      expect(_times(a.keys), [0, 3, 4]);
      expect(_opacities(a.keys), [1, 1, 0]);
      final b = _layer(plan, 'B.fx0-vignette');
      expect(b.start, 3);
      expect(_times(b.keys), [0, 1, 4]);
      expect(_opacities(b.keys), [0, 1, 1]);
      // Fading out while dissolving: t·(1 − t), sampled every 0.1 s.
      final fade = _layer(plan, 'A.fadeOut');
      expect(fade.start, 3);
      expect(fade.keys, hasLength(11));
      for (final key in fade.keys) {
        expect(key.opacity, closeTo(key.t * (1 - key.t), 1e-9));
      }
    });

    test('sun rays rotate and flicker on an oversized texture', () {
      final plan = _compile([
        _photo('A', seconds: 2, effects: [ClipEffect(EffectType.sunRays)]),
      ]);
      final rays = _layer(plan, 'A.fx0-sunRays');
      expect(
        rays.source,
        const GeneratedSource(
          EffectTexture(EffectType.sunRays, 0.4, 1280, 720),
        ),
      );
      expect(rays.keys, hasLength(21));
      final k = rays.keys[5];
      expect(k.t, closeTo(0.5, 1e-12));
      expect([k.x, k.y, k.w, k.h], _closeToList([-288, -162, 2496, 1404]));
      expect(k.rotation, closeTo(3 * math.sin(2 * math.pi * 0.5 / 6), 1e-9));
      expect(
        k.opacity,
        closeTo(0.85 + 0.15 * math.sin(2 * math.pi * 0.5 / 2.3), 1e-9),
      );
    });

    test('caustics drift diagonally and bounce inside the margin', () {
      final plan = _compile([
        _photo('A', seconds: 30, effects: [ClipEffect(EffectType.caustics)]),
      ]);
      final caustics = _layer(plan, 'A.fx0-caustics');
      expect(
        caustics.source,
        const GeneratedSource(
          EffectTexture(EffectType.caustics, 0.35, 1920, 1080),
        ),
      );
      final v = 0.04 * 1920 / math.sqrt2;
      final start = TimelineRenderPlan.evaluateLayer(caustics, 0);
      expect((start.x, start.y, start.w, start.h), (-480, -270, 2400, 1350));
      final one = TimelineRenderPlan.evaluateLayer(caustics, 1);
      expect(one.x, closeTo(-480 + v, 1e-6));
      expect(one.y, closeTo(-270 + v, 1e-6));
      final six = TimelineRenderPlan.evaluateLayer(caustics, 6);
      expect(six.y, closeTo(-270 + (540 - 6 * v), 1e-6));
      for (final key in caustics.keys) {
        expect(key.x, inInclusiveRange(-480 - 1e-6, 1e-6));
        expect(key.y, inInclusiveRange(-270 - 1e-6, 1e-6));
      }
    });
  });

  group('overlays', () {
    test('rect comes from centre, width fraction, and aspect', () {
      final overlay = _image(
        'o',
        start: 1,
        seconds: 2,
      ).copyWith(rotation: 15, opacity: 0.8);
      final plan = _compile([_photo('A')], overlays: [overlay]);
      final layer = _layer(plan, 'o');
      expect(layer.kind, PlanLayerKind.image);
      expect(layer.source, const FileSource('/media/o.png'));
      expect((layer.start, layer.duration), (1, 2));
      expect((layer.sourceStart, layer.sourceDuration, layer.speed), (0, 2, 1));
      expect(layer.grade, isNull);
      expect(layer.look, isNull);
      expect(layer.keys, hasLength(1));
      final k = layer.keys.single;
      expect((k.x, k.y, k.w, k.h), (0, 570, 960, 480));
      expect((k.rotation, k.opacity), (15, 0.8));
    });

    test('pop scales about the centre while fading', () {
      final overlay = _image('o').copyWith(
        animationIn: OverlayAnimation.pop,
        animationOut: OverlayAnimation.fade,
      );
      final layer = _layer(_compile([_photo('A')], overlays: [overlay]), 'o');
      expect(_times(layer.keys), _closeToList([0, 0.24, 0.4, 2.6, 3]));
      expect(_opacities(layer.keys), _closeToList([0, 0.6, 1, 1, 0]));
      expect([
        for (final k in layer.keys) k.w / 960,
      ], _closeToList([0.6, 1.08, 1, 1, 1]));
      for (final k in layer.keys) {
        expect(k.x + k.w / 2, closeTo(480, 1e-9));
        expect(k.y + k.h / 2, closeTo(810, 1e-9));
      }
      final mid = TimelineRenderPlan.evaluateLayer(layer, 0.12);
      expect(mid.w, closeTo(960 * 0.84, 1e-9));
      expect(mid.opacity, closeTo(0.3, 1e-9));
    });

    test('slide up enters from below and leaves upwards', () {
      final overlay = _image('o').copyWith(
        animationIn: OverlayAnimation.slideUp,
        animationOut: OverlayAnimation.slideUp,
      );
      final layer = _layer(_compile([_photo('A')], overlays: [overlay]), 'o');
      final first = layer.keys.first, last = layer.keys.last;
      expect(first.y, closeTo(570 + 0.08 * 1080, 1e-9));
      expect(first.opacity, 0);
      expect(
        TimelineRenderPlan.evaluateLayer(layer, 0.4).y,
        closeTo(570, 1e-9),
      );
      expect(last.y, closeTo(570 - 0.08 * 1080, 1e-9));
      expect(last.opacity, 0);
    });

    test('fades multiply with animations on a sampled curve', () {
      final overlay = _image(
        'o',
      ).copyWith(fadeIn: 0.5, opacity: 0.5, animationIn: OverlayAnimation.fade);
      final layer = _layer(_compile([_photo('A')], overlays: [overlay]), 'o');
      expect(_times(layer.keys), _closeToList([0, 0.1, 0.2, 0.3, 0.4, 0.5, 3]));
      for (final k in layer.keys) {
        final expected = 0.5 * math.min(1, k.t / 0.5) * math.min(1, k.t / 0.4);
        expect(k.opacity, closeTo(expected, 1e-9));
      }
    });

    test('video overlays keep speed, grade, look, and overlay effects', () {
      final overlay = TimelineOverlay(
        id: 'v',
        kind: OverlayKind.video,
        path: '/media/v.mov',
        start: 0.5,
        sourceStart: 2,
        sourceEnd: 6,
        speed: 2,
        grade: RestorationPreset.vivid.settings,
        look: LutProfile.coralWarm,
        effects: [
          ClipEffect(EffectType.sepia),
          ClipEffect(EffectType.vignette),
          ClipEffect(EffectType.softFocus, intensity: 1),
        ],
      );
      final plan = _compile([_photo('A')], overlays: [overlay]);
      final layer = _layer(plan, 'v');
      expect(layer.kind, PlanLayerKind.video);
      expect((layer.start, layer.duration), (0.5, 2));
      expect((layer.sourceStart, layer.sourceDuration, layer.speed), (2, 4, 2));
      expect(layer.grade!.toJson(), RestorationPreset.vivid.settings.toJson());
      expect(layer.look!.kind, LutKind.coralWarm);
      expect(
        layer.filters.colorMatrix,
        _closeToList(ColorMatrices.forEffect(EffectType.sepia, 0.8)),
      );
      expect(layer.filters.blurSigma, closeTo(6, 1e-12));
      // The vignette is not overlay-safe: no extra layer.
      expect(plan.layers, hasLength(1));
    });

    test('titles become generated images sized for their rect', () {
      const title = TitleSpec(text: 'Blue Hole');
      final overlay = TimelineOverlay(
        id: 't',
        kind: OverlayKind.text,
        widthFraction: 0.4,
        mediaAspect: 4,
        title: title,
        animationIn: OverlayAnimation.pop,
      );
      final plan = _compile([_photo('A')], overlays: [overlay]);
      final layer = _layer(plan, 't');
      expect(layer.kind, PlanLayerKind.image);
      expect(
        layer.source,
        const GeneratedSource(
          TitleTexture(
            title,
            width: 829,
            canvasWidth: 1920,
            canvasHeight: 1080,
          ),
        ),
      );
      expect(layer.keys.last.h, closeTo(192, 1e-9));
      final measured = _compile(
        [_photo('A')],
        overlays: [overlay],
        titleAspect: (spec, w, h) => 3,
      );
      expect(_layer(measured, 't').keys.last.h, closeTo(256, 1e-9));
      final empty = _compile(
        [_photo('A')],
        overlays: [overlay.copyWith(title: const TitleSpec(text: '  '))],
      );
      expect(empty.layers, isEmpty);
    });

    test('are trimmed to the movie, out animations at the new end', () {
      final plan = _compile(
        [_photo('A')],
        overlays: [
          const TimelineOverlay(
            id: 'v',
            kind: OverlayKind.video,
            path: '/media/v.mov',
            start: 3,
            sourceStart: 1,
            sourceEnd: 11,
            speed: 2,
            fadeOut: 0.5,
          ),
          _image('late', start: 4.5),
          _image(
            'i',
            start: 2,
            seconds: 5,
          ).copyWith(animationOut: OverlayAnimation.fade),
        ],
      );
      final video = _layer(plan, 'v');
      expect((video.start, video.duration), (3, 1));
      expect((video.sourceStart, video.sourceDuration), (1, 2));
      expect(_times(video.keys), [0, 0.5, 1]);
      expect(_opacities(video.keys), [1, 1, 0]);
      expect(plan.layers.any((l) => l.id == 'late'), isFalse);
      final image = _layer(plan, 'i');
      expect(image.duration, 2);
      expect(_times(image.keys), _closeToList([0, 1.6, 2]));
      final audio = plan.audio.singleWhere((a) => a.id == 'v');
      expect((audio.start, audio.sourceDuration, audio.speed), (3, 2, 2));
      expect(audio.duration, 1);
      expect(audio.fadeOut, 0.5);
    });
  });

  group('audio', () {
    test('main clips, video overlays, and items become segments', () {
      final plan = _compile(
        [
          _video('A', 0, 8).copyWith(volume: 0.5, fadeIn: 0.2),
          _video('B', 0, 6, speed: 2, transition: ClipTransition.crossfade),
          _photo('C', seconds: 2, transition: ClipTransition.crossfade),
          _video('D', 0, 4).copyWith(muted: true),
        ],
        transitionSeconds: 1,
        overlays: [
          const TimelineOverlay(
            id: 'ov',
            kind: OverlayKind.video,
            path: '/media/ov.mov',
            start: 2,
            sourceEnd: 3,
            volume: 0.8,
            fadeIn: 0.3,
          ),
          const TimelineOverlay(
            id: 'quiet',
            kind: OverlayKind.video,
            path: '/media/q.mov',
            sourceEnd: 3,
            muted: true,
          ),
          _image('img'),
        ],
        audio: const [
          TimelineAudioClip(
            id: 'music',
            path: '/media/music.m4a',
            start: 1,
            sourceStart: 5,
            sourceEnd: 65,
            volume: 0.6,
            fadeIn: 2,
            fadeOut: 3,
          ),
          TimelineAudioClip(
            id: 'late',
            path: '/media/late.m4a',
            start: 20,
            sourceDuration: 5,
          ),
        ],
      );
      expect(plan.duration, 15);
      expect(plan.audio.map((a) => a.id), ['A', 'B', 'ov', 'music']);
      final a = plan.audio[0];
      expect(a.origin, PlanAudioOrigin.mainClip);
      expect((a.start, a.sourceStart, a.sourceDuration, a.speed), (0, 0, 8, 1));
      expect((a.volume, a.fadeIn, a.fadeOut), (0.5, 0.2, 1));
      final b = plan.audio[1];
      expect((b.start, b.sourceDuration, b.speed, b.duration), (7, 6, 2, 3));
      expect((b.fadeIn, b.fadeOut), (1, 1));
      final ov = plan.audio[2];
      expect(ov.origin, PlanAudioOrigin.overlay);
      expect(
        (ov.start, ov.sourceDuration, ov.volume, ov.fadeIn),
        (2, 3, 0.8, 0.3),
      );
      final music = plan.audio[3];
      expect(music.origin, PlanAudioOrigin.track);
      expect((music.start, music.sourceStart), (1, 5));
      expect(music.sourceDuration, 14);
      expect((music.volume, music.fadeIn, music.fadeOut), (0.6, 2, 3));
    });

    test('lanes never hold overlapping segments', () {
      PlanAudio seg(String id, double start, double length) => PlanAudio(
        id: id,
        path: '/$id',
        origin: PlanAudioOrigin.track,
        start: start,
        sourceStart: 0,
        sourceDuration: length,
        speed: 1,
        volume: 1,
        fadeIn: 0,
        fadeOut: 0,
      );
      final packed = TimelineCompiler.packAudioLanes([
        seg('a', 0, 8),
        seg('b', 7, 3),
        seg('c', 1, 4),
        seg('d', 8, 2),
        seg('e', 10, 1),
        seg('f', 7.5, 1),
      ]);
      expect(
        {for (final s in packed) s.id: s.lane},
        {'a': 0, 'b': 1, 'c': 1, 'd': 0, 'e': 0, 'f': 2},
      );
      for (final x in packed) {
        for (final y in packed) {
          if (x == y || x.lane != y.lane) continue;
          expect(x.end <= y.start + 1e-9 || y.end <= x.start + 1e-9, isTrue);
        }
      }
    });
  });

  group('plan helpers', () {
    test('evaluateLayer interpolates and clamps', () {
      const layer = PlanLayer(
        id: 'l',
        kind: PlanLayerKind.color,
        source: ColorSource(0xFF000000),
        start: 2,
        duration: 2,
        keys: [
          LayerKey(t: 0, x: 0, y: 0, w: 100, h: 50, opacity: 0),
          LayerKey(
            t: 1,
            x: 10,
            y: 20,
            w: 200,
            h: 100,
            rotation: 10,
            opacity: 1,
          ),
        ],
      );
      final mid = TimelineRenderPlan.evaluateLayer(layer, 0.25);
      expect(
        [mid.t, mid.x, mid.y, mid.w, mid.h, mid.rotation, mid.opacity],
        [0.25, 2.5, 5, 125, 62.5, 2.5, 0.25],
      );
      expect(TimelineRenderPlan.evaluateLayer(layer, -1).opacity, 0);
      expect(TimelineRenderPlan.evaluateLayer(layer, 5).w, 200);
      expect(TimelineRenderPlan.evaluateLayer(layer, 5).t, 5);
      expect(layer.sourceDuration, 2);
    });

    test('evaluateClip is identity without keys', () {
      final clip = _compile([_photo('A')]).clips.single;
      final key = TimelineRenderPlan.evaluateClip(clip, 1.5);
      expect((key.t, key.scale, key.x, key.y, key.rotation), (1.5, 1, 0, 0, 0));
    });

    test('active clips and layers at a time', () {
      final plan = _compile(
        [_photo('A'), _photo('B', transition: ClipTransition.crossfade)],
        transitionSeconds: 1,
        overlays: [_image('o', start: 1, seconds: 1)],
      );
      expect(plan.clipsAt(3.5).map((c) => c.id), ['A', 'B']);
      expect(plan.clipsAt(1).map((c) => c.id), ['A']);
      expect(plan.clipsAt(plan.duration).map((c) => c.id), ['B']);
      expect(TimelineRenderPlan.dissolveAt(plan.clips[1], 3.25), 0.25);
      expect(TimelineRenderPlan.dissolveAt(plan.clips[0], 3.25), 1);
      expect(plan.layersAt(1.5).map((l) => l.id), ['o']);
      expect(plan.layersAt(2), isEmpty);
    });

    test('identical textures are generated once', () {
      final plan = _compile([
        _photo('A', effects: [ClipEffect(EffectType.vignette)]),
        _photo('B', effects: [ClipEffect(EffectType.vignette)]),
        _photo('C', effects: [ClipEffect(EffectType.vignette, intensity: 1)]),
      ]);
      expect(plan.layers, hasLength(3));
      expect(plan.generatedSpecs, hasLength(2));
    });

    test('an empty project compiles to an empty plan', () {
      final plan = _compile(
        const [],
        overlays: [_image('o')],
        audio: const [TimelineAudioClip(id: 'm', path: '/m', sourceEnd: 5)],
      );
      expect(plan.duration, 0);
      expect(plan.clips, isEmpty);
      expect(plan.layers, isEmpty);
      expect(plan.audio, isEmpty);
    });
  });
}
