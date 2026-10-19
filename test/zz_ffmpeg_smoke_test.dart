// TEMPORARY smoke render; deleted after use.
import 'dart:io';

import 'package:aqua_recover/core/processing/ffmpeg_video_backend.dart';
import 'package:aqua_recover/core/timeline/ffmpeg_timeline_renderer.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_render_plan.dart';
import 'package:aqua_recover/core/timeline/timeline_render_service.dart';
import 'package:aqua_recover/core/timeline/timeline_textures.dart';
import 'package:flutter_test/flutter_test.dart';

const m = '/tmp/claude-0/-home-claude-aquarecover/6e2d894a-d15f-5b3f-8242-f449929636fa/scratchpad/ffsmoke';
const out = '/tmp/claude-0/-home-claude-aquarecover/6e2d894a-d15f-5b3f-8242-f449929636fa/scratchpad/ffv2/out';

TimelineProject smoke() => TimelineProject(
  id: 'smoke',
  quality: TimelineQuality.hd,
  clips: [
    TimelineClip(id: 'a', path: '$m/a.mp4', kind: TimelineClipKind.video,
        sourceStart: 0, sourceEnd: 5, sourceDuration: 8,
        effects: [ClipEffect(EffectType.sunRays, intensity: 1), ClipEffect(EffectType.grain, intensity: 0.5)]),
    TimelineClip(id: 'b', path: '$m/b.mp4', kind: TimelineClipKind.video,
        sourceStart: 0, sourceEnd: 8, sourceDuration: 10, speed: 2,
        transition: ClipTransition.crossfade, fadeOut: 0.5, fadeColor: FadeColor.white,
        effects: [ClipEffect(EffectType.vignette, intensity: 1), ClipEffect(EffectType.clarity), ClipEffect(EffectType.swell, intensity: 1)]),
    TimelineClip(id: 'c', path: '$m/still.jpg', kind: TimelineClipKind.image, stillSeconds: 3,
        transition: ClipTransition.dipBlack, motion: ClipMotion.zoomIn,
        effects: [ClipEffect(EffectType.cinemaBars), ClipEffect(EffectType.drift)]),
    TimelineClip(id: 'd', path: '$m/silent.mp4', kind: TimelineClipKind.video,
        sourceStart: 0, sourceEnd: 3, sourceDuration: 3,
        transition: ClipTransition.dipWhite,
        effects: [ClipEffect(EffectType.mono), ClipEffect(EffectType.caustics, intensity: 1), ClipEffect(EffectType.softFocus)]),
  ],
  overlays: const [
    TimelineOverlay(id: 'photo', kind: OverlayKind.image, path: '$m/photo.png',
        start: 1, stillSeconds: 3, centerX: 0.75, centerY: 0.3, widthFraction: 0.3,
        mediaAspect: 4 / 3, rotation: 10, animationIn: OverlayAnimation.pop, fadeOut: 0.5),
    TimelineOverlay(id: 'title', kind: OverlayKind.text, lane: 1, start: 0.5, stillSeconds: 4,
        centerY: 0.8, widthFraction: 0.45, mediaAspect: 5,
        animationIn: OverlayAnimation.slideUp, animationOut: OverlayAnimation.fade,
        title: TitleSpec(text: 'Blue Hole', style: TitleStyle.boldBox)),
    TimelineOverlay(id: 'pip', kind: OverlayKind.video, path: '$m/a.mp4', start: 9,
        sourceStart: 2, sourceEnd: 4, speed: 0.5, centerX: 0.8, centerY: 0.25,
        widthFraction: 0.3, mediaAspect: 16 / 9, volume: 0.5, fadeIn: 0.5, opacity: 0.8),
  ],
  audioClips: const [
    TimelineAudioClip(id: 'music', path: '$m/music.m4a', sourceDuration: 20, volume: 0.6, fadeIn: 1, fadeOut: 2),
    TimelineAudioClip(id: 'voice', path: '$m/voice.wav', start: 3, sourceDuration: 3, volume: 0.9, fadeIn: 0.3, fadeOut: 0.3),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('smoke render', () async {
    final project = smoke();
    final plan = TimelineCompiler.compile(project, titleAspect: titleAspectRatio);
    final cache = GeneratedTextureCache(directory: () async => Directory('$out/tex'));
    final generated = await TimelineRenderService.writeGeneratedSources(plan, cache);
    final job = FfmpegTimelineRenderer.buildArguments(plan, outputPath: '$out/movie.mp4',
        generatedPaths: generated, cubeFiles: {for (final (i, c) in plan.clips.indexed) c.id: 'c$i.cube'});
    File('$out/graph_preview.txt').writeAsStringSync(job.graph);
    for (final e in job.scripts.entries) { File('$out/${e.key}').writeAsStringSync(e.value); }
    File('$out/args.txt').writeAsStringSync(job.arguments.join('\n'));
    final renderer = FfmpegTimelineRenderer(const FfmpegVideoBackend('/usr/bin/ffmpeg'));
    final progress = <double>[];
    final sw = Stopwatch()..start();
    await renderer.render(project, plan: plan, generatedPaths: generated,
        outputPath: '$out/movie.mp4', onProgress: progress.add);
    print('rendered in ${sw.elapsed}, ${progress.length} progress updates, last ${progress.last}, duration ${plan.duration}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
