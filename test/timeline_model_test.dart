import 'dart:convert';

import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineClip _video(
  String id,
  double start,
  double end, {
  double speed = 1,
  ClipTransition transition = ClipTransition.cut,
}) => TimelineClip(
  id: id,
  path: '/media/$id.mov',
  kind: TimelineClipKind.video,
  sourceStart: start,
  sourceEnd: end,
  sourceDuration: 60,
  speed: speed,
  transition: transition,
);

TimelineClip _photo(String id, {double seconds = 3}) => TimelineClip(
  id: id,
  path: '/media/$id.jpg',
  kind: TimelineClipKind.image,
  stillSeconds: seconds,
);

/// Round-trips through a real JSON string, as the project store does.
Map<String, Object?> _viaJson(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>();

void main() {
  group('clip speed', () {
    test('a 2× clip lasts half its source span', () {
      final clip = _video('v', 10, 20, speed: 2);
      expect(clip.sourceSpan, 10);
      expect(clip.duration, 5);
      expect(clip.sourceTimeAt(1.5), 13);
    });

    test('speed is clamped to 0.25…4 and photos ignore it', () {
      expect(_video('v', 0, 8, speed: 10).playbackSpeed, 4);
      expect(_video('v', 0, 8, speed: 10).duration, 2);
      expect(_video('v', 0, 8, speed: 0.1).duration, 32);
      final photo = TimelineClip(
        id: 'p',
        path: '/p.jpg',
        kind: TimelineClipKind.image,
        speed: 3,
      );
      expect(photo.playbackSpeed, 1);
      expect(photo.duration, 3);
    });

    test('layout uses the speed-aware duration', () {
      final project = TimelineProject(
        id: 'p',
        transitionSeconds: 1,
        clips: [
          _video('a', 0, 8, speed: 2),
          _video('b', 0, 6, speed: 0.5, transition: ClipTransition.crossfade),
        ],
      );
      final entries = project.layout.entries;
      expect(entries[0].duration, 4);
      expect(entries[1].start, 3);
      expect(entries[1].duration, 12);
      expect(project.duration, 15);
      expect(entries[1].sourceTime(5), closeTo(1, 1e-9));
    });

    test('dip transitions do not overlap clips', () {
      final project = TimelineProject(
        id: 'p',
        clips: [
          _photo('a'),
          _photo('b').copyWith(transition: ClipTransition.dipBlack),
          _photo('c').copyWith(transition: ClipTransition.dipWhite),
        ],
      );
      expect(project.layout.entries.map((e) => e.start), [0, 3, 6]);
      expect(project.layout.entries.map((e) => e.overlapIn), [0, 0, 0]);
      expect(ClipTransition.dipBlack.isDip, isTrue);
      expect(ClipTransition.crossfade.isDip, isFalse);
    });
  });

  group('split', () {
    test('cuts a fast video at source time and keeps its settings', () {
      final clip = _video('v', 10, 30, speed: 2).copyWith(
        volume: 0.4,
        fadeIn: 1,
        fadeOut: 2,
        fadeColor: FadeColor.deepBlue,
        effects: [ClipEffect(EffectType.grain), ClipEffect(EffectType.mono)],
        look: LutProfile.blueWater,
        grade: RestorationPreset.deep.settings,
        transition: ClipTransition.crossfade,
      );
      final (left, right) = clip.splitAt(3, newId: 'w')!;
      expect((left.sourceStart, left.sourceEnd), (10, 16));
      expect((right.sourceStart, right.sourceEnd), (16, 30));
      expect(left.duration + right.duration, clip.duration);
      expect(right.id, 'w');
      for (final half in [left, right]) {
        expect(half.speed, 2);
        expect(half.volume, 0.4);
        expect(half.effects, clip.effects);
        expect(half.look.kind, LutKind.blueWater);
        expect(half.grade.toJson(), clip.grade.toJson());
        expect(half.fadeColor, FadeColor.deepBlue);
      }
      expect((left.fadeIn, left.fadeOut), (1, 0));
      expect((right.fadeIn, right.fadeOut), (0, 2));
      expect(left.transition, ClipTransition.crossfade);
      expect(right.transition, ClipTransition.cut);
    });

    test('splits a photo by still seconds', () {
      final (left, right) = _photo('p', seconds: 5)
          .copyWith(motion: ClipMotion.zoomIn, fadeIn: 1, fadeOut: 1)
          .splitAt(2, newId: 'q')!;
      expect((left.stillSeconds, right.stillSeconds), (2, 3));
      expect(right.motion, ClipMotion.zoomIn);
      expect((left.fadeOut, right.fadeIn), (0, 0));
    });

    test('refuses slivers measured in timeline seconds', () {
      // 4 s of source at 4× is 1 s on the timeline.
      expect(_video('v', 0, 4, speed: 4).splitAt(0.6, newId: 'x'), isNull);
    });
  });

  group('clip audio and fades', () {
    test('gain is the volume unless muted', () {
      expect(_video('v', 0, 4).copyWith(volume: 0.3).gain, 0.3);
      expect(_video('v', 0, 4).copyWith(volume: 0.3, muted: true).gain, 0);
    });

    test('fades are clamped to 3 s each and to the clip', () {
      final long = _video('v', 0, 20).copyWith(fadeIn: 9, fadeOut: 1);
      expect(long.fades, (fadeIn: 3, fadeOut: 1));
      final short = _photo('p', seconds: 2).copyWith(fadeIn: 3, fadeOut: 1);
      expect(short.fades.fadeIn, closeTo(1.5, 1e-9));
      expect(short.fades.fadeOut, closeTo(0.5, 1e-9));
    });

    test('fade colours', () {
      expect(FadeColor.black.argb, 0xFF000000);
      expect(FadeColor.white.argb, 0xFFFFFFFF);
      expect(FadeColor.deepBlue.argb, 0xFF06263F);
    });
  });

  group('overlays', () {
    test('durations follow kind and speed', () {
      const video = TimelineOverlay(
        id: 'o',
        kind: OverlayKind.video,
        path: '/o.mov',
        sourceStart: 2,
        sourceEnd: 8,
        speed: 3,
      );
      expect(video.duration, 2);
      expect(video.end, 2);
      const image = TimelineOverlay(
        id: 'i',
        kind: OverlayKind.image,
        path: '/i.png',
        start: 4,
        stillSeconds: 5,
        speed: 3,
      );
      expect(image.duration, 5);
      expect(image.end, 9);
      expect(image.playbackSpeed, 1);
    });

    test('only overlay-safe effects are rendered', () {
      final overlay = TimelineOverlay(
        id: 'o',
        kind: OverlayKind.image,
        path: '/i.png',
        effects: [
          ClipEffect(EffectType.sepia),
          ClipEffect(EffectType.vignette),
          ClipEffect(EffectType.swell),
        ],
      );
      expect(overlay.renderedEffects.map((e) => e.type), [EffectType.sepia]);
    });

    test('split keeps in effects on the first half, out on the second', () {
      const overlay = TimelineOverlay(
        id: 'o',
        kind: OverlayKind.video,
        path: '/o.mov',
        start: 5,
        sourceStart: 1,
        sourceEnd: 9,
        speed: 2,
        fadeIn: 0.5,
        fadeOut: 0.7,
        animationIn: OverlayAnimation.pop,
        animationOut: OverlayAnimation.fade,
      );
      final (a, b) = overlay.splitAt(1, newId: 'p')!;
      expect((a.start, a.sourceStart, a.sourceEnd), (5, 1, 3));
      expect((b.start, b.sourceStart, b.sourceEnd), (6, 3, 9));
      expect((a.fadeIn, a.fadeOut, b.fadeIn, b.fadeOut), (0.5, 0, 0, 0.7));
      expect(a.animationIn, OverlayAnimation.pop);
      expect(a.animationOut, OverlayAnimation.none);
      expect(b.animationIn, OverlayAnimation.none);
      expect(b.animationOut, OverlayAnimation.fade);
      expect(b.id, 'p');
      expect(overlay.splitAt(0.05, newId: 'x'), isNull);
    });

    test('round-trips through JSON', () {
      final overlay = TimelineOverlay(
        id: 'o',
        kind: OverlayKind.text,
        lane: 2,
        start: 1.5,
        stillSeconds: 4,
        effects: [ClipEffect(EffectType.cyanotype, intensity: 0.3)],
        centerX: 0.3,
        centerY: 0.8,
        widthFraction: 0.6,
        rotation: -12,
        opacity: 0.9,
        fadeIn: 0.2,
        fadeOut: 0.4,
        mediaAspect: 3.2,
        animationIn: OverlayAnimation.slideUp,
        animationOut: OverlayAnimation.pop,
        title: const TitleSpec(
          text: 'Blue Hole\n32 m',
          style: TitleStyle.diveStamp,
          color: 0xFFFFE082,
          backgroundColor: 0x80000000,
          fontScale: 0.06,
          align: TitleAlign.left,
          bold: false,
        ),
      );
      final restored = TimelineOverlay.fromJson(_viaJson(overlay.toJson()));
      expect(restored.toJson(), overlay.toJson());
      expect(restored.title, overlay.title);

      final video = TimelineOverlay(
        id: 'v',
        kind: OverlayKind.video,
        path: '/v.mov',
        sourceStart: 1,
        sourceEnd: 5,
        sourceDuration: 10,
        speed: 1.5,
        volume: 0.5,
        muted: true,
        grade: RestorationPreset.vivid.settings,
        look: LutProfile.coralWarm,
      );
      final back = TimelineOverlay.fromJson(_viaJson(video.toJson()));
      expect(back.toJson(), video.toJson());
      expect(back.grade, isNotNull);
      expect(
        TimelineOverlay.fromJson(_viaJson({'id': 'x', 'kind': 'image'})).grade,
        isNull,
      );
    });
  });

  group('titles', () {
    test('JSON keeps every field and unknown values fall back', () {
      const spec = TitleSpec(
        text: 'Manta',
        style: TitleStyle.boldBox,
        color: 0xFF112233,
        backgroundColor: 0xFF0A84FF,
        fontScale: 0.1,
        align: TitleAlign.right,
      );
      expect(TitleSpec.fromJson(_viaJson(spec.toJson())), spec);
      final fallback = TitleSpec.fromJson({'text': 'x', 'style': 'neon'});
      expect(fallback.style, TitleStyle.classic);
      expect(fallback.fontScale, TitleSpec.defaultFontScale);
      expect(fallback.bold, isTrue);
    });
  });

  group('audio items', () {
    test('duration, split, and JSON', () {
      const music = TimelineAudioClip(
        id: 'm',
        name: 'Reef song',
        path: '/m.m4a',
        role: AudioRole.music,
        lane: 1,
        start: 2,
        sourceStart: 10,
        sourceEnd: 70,
        sourceDuration: 200,
        volume: 0.6,
        fadeIn: 2,
        fadeOut: 4,
      );
      expect(music.duration, 60);
      expect(music.end, 62);
      expect(music.fades, (fadeIn: 2, fadeOut: 4));
      final (a, b) = music.splitAt(20, newId: 'n')!;
      expect((a.sourceStart, a.sourceEnd, a.fadeIn, a.fadeOut), (10, 30, 2, 0));
      expect((b.start, b.sourceStart, b.sourceEnd), (22, 30, 70));
      expect((b.fadeIn, b.fadeOut, b.id), (0, 4, 'n'));
      final restored = TimelineAudioClip.fromJson(_viaJson(music.toJson()));
      expect(restored.toJson(), music.toJson());
      expect(
        const TimelineAudioClip(
          id: 'u',
          path: '/u.wav',
          sourceDuration: 7,
        ).duration,
        7,
      );
    });
  });

  group('effects', () {
    test('JSON round-trip and defaults from the catalogue', () {
      final effect = ClipEffect(EffectType.sunRays);
      expect(effect.intensity, 0.4);
      expect(ClipEffect.fromJson(_viaJson(effect.toJson())), effect);
      expect(
        ClipEffect.fromJson({'type': 'vignette', 'intensity': 4}).intensity,
        1,
      );
      expect(
        () => ClipEffect.fromJson({'type': 'hologram'}),
        throwsFormatException,
      );
      expect(
        ClipEffect.listFromJson({
          'effects': [
            {'type': 'mono'},
            {'type': 'hologram'},
            'junk',
          ],
        }, 'effects'),
        [ClipEffect(EffectType.mono)],
      );
    });
  });

  group('project', () {
    test('v2 round-trips every new field', () {
      final project = TimelineProject(
        id: 'p',
        name: 'Reef day',
        aspect: TimelineAspect.vertical45,
        clips: [
          _video('a', 1, 9, speed: 2).copyWith(
            volume: 0.5,
            fadeIn: 0.5,
            fadeOut: 1,
            fadeColor: FadeColor.white,
            effects: [
              ClipEffect(EffectType.grain),
              ClipEffect(EffectType.vignette, intensity: 0.7),
            ],
          ),
          _photo('b').copyWith(transition: ClipTransition.dipWhite),
        ],
        overlays: const [
          TimelineOverlay(
            id: 'o',
            kind: OverlayKind.image,
            path: '/o.png',
            animationIn: OverlayAnimation.pop,
          ),
        ],
        audioClips: const [
          TimelineAudioClip(id: 'm', path: '/m.m4a', sourceDuration: 30),
        ],
      );
      final json = _viaJson(project.toJson());
      expect(json['version'], 2);
      expect(json['audio'], hasLength(1));
      expect(json['overlays'], hasLength(1));
      final restored = TimelineProject.fromJson(json);
      expect(restored.toJson(), project.toJson());
      expect(restored.clips.first.effects, project.clips.first.effects);
    });

    test('v1 projects load with v2 defaults', () {
      final v1 = {
        'format': 'aquarecover.timeline',
        'version': 1,
        'id': 'old',
        'name': 'Old dive',
        'aspect': 'portrait',
        'quality': 'hd',
        'frameRate': 25,
        'transitionSeconds': 0.8,
        'clips': [
          {
            'id': 'c',
            'path': '/c.mov',
            'kind': 'video',
            'sourceStart': 1,
            'sourceEnd': 5,
            'sourceDuration': 9,
            'stillSeconds': 3,
            'grade': RestorationPreset.natural.settings.toJson(),
            'look': LutProfile.greenWater.toJson(),
            'transition': 'crossfade',
            'motion': 'none',
            'muted': true,
          },
        ],
      };
      final project = TimelineProject.fromJson(_viaJson(v1));
      final clip = project.clips.single;
      expect(clip.speed, 1);
      expect(clip.volume, 1);
      expect(clip.muted, isTrue);
      expect(clip.gain, 0);
      expect((clip.fadeIn, clip.fadeOut), (0, 0));
      expect(clip.fadeColor, FadeColor.black);
      expect(clip.effects, isEmpty);
      expect(clip.duration, 4);
      expect(project.overlays, isEmpty);
      expect(project.audioClips, isEmpty);
      expect(project.aspect, TimelineAspect.portrait);
      expect(project.toJson()['version'], 2);
    });

    test('rejects formats newer than 2', () {
      expect(
        () => TimelineProject.fromJson({'id': 'p', 'version': 3}),
        throwsFormatException,
      );
      expect(TimelineProject.fromJson({'id': 'p', 'version': 2}).id, 'p');
    });

    test('4:5 is appended so older aspect indices stay', () {
      expect(TimelineAspect.values.last, TimelineAspect.vertical45);
      expect(TimelineAspect.values.indexOf(TimelineAspect.square), 2);
      expect(TimelineAspect.vertical45.label, 'Portrait 4:5');
      expect(
        const TimelineProject(
          id: 'p',
          aspect: TimelineAspect.vertical45,
        ).outputSize,
        (width: 1080, height: 1350),
      );
    });

    test('duration stays the main track length', () {
      final project = TimelineProject(
        id: 'p',
        clips: [_photo('a')],
        audioClips: const [
          TimelineAudioClip(id: 'm', path: '/m.m4a', sourceDuration: 300),
        ],
        overlays: const [
          TimelineOverlay(
            id: 'o',
            kind: OverlayKind.image,
            path: '/o.png',
            start: 2,
            stillSeconds: 10,
          ),
        ],
      );
      expect(project.duration, 3);
    });
  });
}
