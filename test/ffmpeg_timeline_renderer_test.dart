import 'package:aqua_recover/core/timeline/ffmpeg_timeline_renderer.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_render_plan.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineClip _video(
  String id, {
  double start = 0,
  double end = 4,
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

FfmpegTimelineJob _job(
  TimelineProject project, {
  Map<String, String> generated = const {},
  bool Function(String path)? hasAudio,
}) {
  final plan = TimelineCompiler.compile(project);
  return FfmpegTimelineRenderer.buildArguments(
    plan,
    outputPath: '/out/movie.mp4',
    generatedPaths: generated,
    cubeFiles: {for (final (i, c) in plan.clips.indexed) c.id: 'c$i.cube'},
    hasAudio: hasAudio,
  );
}

/// The graph statement that defines [label].
String _chain(String graph, String label) =>
    graph.split(';\n').firstWhere((s) => s.trimRight().endsWith('[$label]'));

void main() {
  test('a 2× clip is retimed, normalised, graded, and its sound sped up', () {
    final job = _job(
      TimelineProject(
        id: 'p',
        clips: [_video('a', start: 2, end: 10, speed: 2)],
      ),
    );
    expect(
      job.arguments,
      containsAllInOrder(['-ss', '2', '-t', '8.066667', '-i', '/media/a.mov']),
    );
    expect(
      job.arguments,
      containsAllInOrder(['-filter_complex_script', 'graph.txt']),
    );
    final clip = _chain(job.graph, 'm0');
    expect(
      clip,
      startsWith(
        '[0:v]setpts=(PTS-STARTPTS)/2,fps=30,tpad=stop=-1:stop_mode=clone,'
        'trim=end_frame=120,settb=1/30,setpts=N,'
        'scale=1920:1080:force_original_aspect_ratio=decrease',
      ),
    );
    expect(clip, contains('format=gbrp,lut3d=file=c0.cube:interp=tetrahedral'));
    expect(clip, endsWith('pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black[m0]'));
    final sound = _chain(job.graph, 's0');
    expect(sound, contains('asetpts=PTS-STARTPTS,atempo=2,'));
    expect(sound, contains('apad=whole_len=192000,atrim=end_sample=192000'));
    expect(job.graph, contains('[vout]'));
    expect(job.arguments, containsAllInOrder(['-c:v', 'libx264']));
    expect(job.arguments, containsAllInOrder(['-c:a', 'aac']));
    expect(job.arguments, containsAllInOrder(['-colorspace', 'bt709']));
  });

  test('effects become blur, sharpen, and monochrome luma grain', () {
    final job = _job(
      TimelineProject(
        id: 'p',
        clips: [
          _video(
            'a',
            effects: [
              ClipEffect(EffectType.softFocus, intensity: 0.5),
              ClipEffect(EffectType.clarity, intensity: 1),
              ClipEffect(EffectType.grain, intensity: 1),
            ],
          ),
        ],
      ),
    );
    final clip = _chain(job.graph, 'm0');
    expect(clip, contains('gblur=sigma=3'));
    expect(clip, contains('unsharp=7:7:1:7:7:1'));
    // std 0.06 of 255 levels = strength/√3 (0.06·255·√3 ≈ 26.5).
    expect(clip, contains('noise=c0s=27:c0f=t'));
    expect(clip, contains('format=yuv444p,'));
    expect(
      clip,
      contains('scale=in_color_matrix=bt709:in_range=pc,format=gbrp'),
    );
  });

  test('a dip is a cut plus a scripted colour layer', () {
    final job = _job(
      TimelineProject(
        id: 'p',
        clips: [
          _video('a'),
          _video('b', transition: ClipTransition.dipWhite),
        ],
      ),
    );
    expect(job.graph, contains('[m0][m1]concat=n=2:v=1:a=0[mx1]'));
    expect(job.graph, isNot(contains('xfade')));
    final dip = _chain(job.graph, 'l0');
    expect(
      dip,
      'color=c=0xffffff@1:s=1920x1080:r=30,format=gbrap,'
      'trim=end_frame=18,settb=1/30,setpts=N+111,'
      'sendcmd=f=l0.cmd,colorchannelmixer@l0=aa=0[l0]',
    );
    expect(
      job.graph,
      contains(
        "[mx1][l0]overlay=x='floor(960-w/2+0.5)':y='floor(540-h/2+0.5)':"
        "eof_action=pass:format=gbrp:enable='between(t,3.683333,4.283333)'[v0]",
      ),
    );
    expect(
      job.scripts['l0.cmd'],
      '# opacity of layer b.dip\n'
      "3.7-4 [expr] colorchannelmixer@l0 aa '0+1*TI';\n"
      "4-4.3 [expr] colorchannelmixer@l0 aa '1-1*TI';\n"
      '4.3 [enter] colorchannelmixer@l0 aa 0;\n',
    );
  });

  test('crossfades use xfade on equal, normalised streams', () {
    final job = _job(
      TimelineProject(
        id: 'p',
        clips: [
          _video('a'),
          _video('b', transition: ClipTransition.crossfade),
        ],
      ),
    );
    expect(
      job.graph,
      contains('[m0][m1]xfade=transition=fade:duration=0.6:offset=3.4[mx1]'),
    );
    expect(_chain(job.graph, 'm1'), contains('trim=end_frame=120'));
  });

  test('moving clips are placed by perspective with key expressions', () {
    final job = _job(
      TimelineProject(
        id: 'p',
        quality: TimelineQuality.hd,
        clips: [
          _video('a', effects: [ClipEffect(EffectType.swell, intensity: 1)]),
        ],
      ),
    );
    final clip = _chain(job.graph, 'm0');
    expect(clip, contains("crop=w='min(iw,1280)':h='min(ih,720)'"));
    expect(clip, contains('pad=1284:724:(ow-iw)/2:(oh-ih)/2:color=black'));
    expect(clip, contains("perspective=x0='if(lt(in,"));
    expect(clip, contains(':sense=destination:interpolation=cubic:eval=frame'));
    expect(clip, endsWith('crop=1280:720:2:2[m0]'));
    // Keys every 0.1 s over 4 s, never one term per frame.
    final x0 = RegExp(r"x0='([^']*)'").firstMatch(clip)!.group(1)!;
    expect('clip('.allMatches(x0).length, lessThanOrEqualTo(40));
  });

  test('a still-zooming photo maps its corners linearly in frames', () {
    final job = _job(
      TimelineProject(
        id: 'p',
        quality: TimelineQuality.hd,
        clips: [
          const TimelineClip(
            id: 'p',
            path: '/media/p.jpg',
            kind: TimelineClipKind.image,
            stillSeconds: 2,
            motion: ClipMotion.zoomIn,
          ),
        ],
      ),
    );
    final clip = _chain(job.graph, 'm0');
    expect(
      clip,
      startsWith('[0:v]scale=1280:720:force_original_aspect_ratio=increase'),
    );
    // The 1284×724 frame grows 1 → 1.15 over 60 frames about its centre.
    expect(clip, contains("x0='-1.605*(clip(in,1,61)-1)'"));
    expect(clip, contains("x3='1284+1.605*(clip(in,1,61)-1)'"));
    expect(
      clip.indexOf('loop=loop=-1:size=1'),
      lessThan(clip.indexOf('perspective')),
    );
  });

  group('layers', () {
    final project = TimelineProject(
      id: 'p',
      clips: [_video('a', end: 8)],
      overlays: const [
        TimelineOverlay(
          id: 'photo',
          kind: OverlayKind.image,
          path: '/media/turtle.jpg',
          start: 1,
          stillSeconds: 3,
          centerX: 0.75,
          centerY: 0.3,
          widthFraction: 0.3,
          mediaAspect: 1.5,
          rotation: 10,
          animationIn: OverlayAnimation.pop,
        ),
        TimelineOverlay(
          id: 'title',
          kind: OverlayKind.text,
          lane: 1,
          start: 0.5,
          stillSeconds: 2.5,
          centerY: 0.8,
          widthFraction: 0.45,
          mediaAspect: 5,
          animationIn: OverlayAnimation.slideUp,
          title: TitleSpec(text: 'Blue Hole'),
        ),
        TimelineOverlay(
          id: 'pip',
          kind: OverlayKind.video,
          path: '/media/pip.mov',
          start: 4,
          sourceStart: 1,
          sourceEnd: 4,
          speed: 0.25,
          centerX: 0.8,
          centerY: 0.8,
          widthFraction: 0.3,
          mediaAspect: 16 / 9,
          volume: 0.5,
          opacity: 0.5,
        ),
      ],
    );
    final job = _job(project, generated: {'title': '/tex/title.png'});

    test('a popping, rotated photo resizes and turns over t', () {
      final photo = _chain(job.graph, 'l0');
      expect(
        photo,
        startsWith('[1:v]format=gbrap,scale=622:415:flags=bicubic'),
      );
      expect(photo, contains('loop=loop=-1:size=1,trim=end_frame=90,'));
      expect(photo, contains('setpts=N+30,sendcmd=f=l0.cmd,'));
      expect(photo, contains("scale=w='max(1,round(if(lt(t,1.24),345.6+"));
      expect(photo, contains(':eval=frame'));
      expect(
        photo,
        endsWith("rotate=a='(10)*PI/180':ow=750:oh=750:c=black@0[l0]"),
      );
      expect(
        job.graph,
        contains(
          "[m0][l0]overlay=x='floor(1440-w/2+0.5)':y='floor(324-h/2+0.5)'",
        ),
      );
      expect(job.scripts['l0.cmd'], contains('colorchannelmixer@l0 aa'));
    });

    test('a sliding title reads its generated PNG', () {
      expect(job.arguments, containsAllInOrder(['-i', '/tex/title.png']));
      expect(
        job.graph,
        contains("y='floor(if(lt(t,0.9),950.4-216*(clip(t,0.5,0.9)-0.5),864)"),
      );
      expect(
        () => _job(project),
        throwsA(isA<StateError>()),
        reason: 'a generated layer without its PNG cannot render',
      );
    });

    test('a video overlay is retimed, faded, and passes at its end', () {
      expect(
        job.arguments,
        containsAllInOrder([
          '-ss',
          '1',
          '-t',
          '1.008333',
          '-i',
          '/media/pip.mov',
        ]),
      );
      final pip = _chain(job.graph, 'l1');
      expect(pip, startsWith('[2:v]setpts=(PTS-STARTPTS)/0.25,fps=30,'));
      expect(pip, contains('setpts=N+120,format=gbrap,'));
      expect(pip, endsWith('colorchannelmixer=aa=0.5[l1]'));
      expect(
        job.graph,
        contains(
          "eof_action=pass:format=gbrp:enable='between(t,3.983333,7.983333)'[v1]",
        ),
      );
      // Its sound at quarter speed: two atempo steps within 0.5…2.
      expect(job.graph, contains('atempo=0.5,atempo=0.5,'));
    });

    test('layers stack in plan order above the main track', () {
      final order = [
        for (final label in ['v0', 'v1', 'v2']) job.graph.indexOf('[$label]'),
      ];
      expect(order, orderedEquals([...order]..sort()));
      expect(job.graph, contains('[v2]scale=out_color_matrix=bt709'));
    });
  });

  test('audio lanes are delayed, concatenated, and mixed unnormalised', () {
    final job = _job(
      TimelineProject(
        id: 'p',
        clips: [_video('a', end: 10)],
        audioClips: const [
          TimelineAudioClip(
            id: 'music',
            path: '/media/music.m4a',
            sourceDuration: 120,
            volume: 0.7,
            fadeIn: 1,
            fadeOut: 2,
          ),
          TimelineAudioClip(
            id: 'voice',
            path: '/media/voice.wav',
            start: 3,
            sourceStart: 0.5,
            sourceDuration: 3,
            fadeIn: 0.3,
            fadeOut: 0.5,
          ),
          TimelineAudioClip(
            id: 'sting',
            path: '/media/sting.wav',
            start: 7,
            sourceDuration: 1,
          ),
        ],
      ),
      hasAudio: (path) => path != '/media/a.mov',
    );
    final graph = job.graph;
    // The silent main clip is skipped; music on lane 1, voice + sting share lane 2.
    expect(graph, isNot(contains('[0:a]')));
    expect(
      _chain(graph, 's1'),
      endsWith('volume=0.7,afade=t=in:st=0:d=1,afade=t=out:st=8:d=2[s1]'),
    );
    expect(
      _chain(graph, 's2'),
      endsWith('afade=t=in:st=0:d=0.3,afade=t=out:st=2:d=0.5[s2]'),
    );
    expect(job.arguments, containsAllInOrder(['-ss', '0.5', '-t', '2.5']));
    expect(graph, contains('[s2]adelay=delays=144000S:all=1[s2d]'));
    expect(graph, contains('[s3]adelay=delays=72000S:all=1[s3d]'));
    expect(graph, contains('[s2d][s3d]concat=n=2:v=0:a=1[lane2]'));
    expect(
      graph,
      contains('anullsrc=r=48000:cl=stereo,atrim=end_sample=480000[abase]'),
    );
    expect(
      graph,
      contains(
        '[abase][s1][lane2]amix=inputs=3:duration=first:'
        'dropout_transition=0:normalize=0,alimiter=limit=0.95:level=0[aout]',
      ),
    );
  });

  test('a movie without sound still gets a silent track', () {
    final job = _job(
      TimelineProject(id: 'p', clips: [_video('a')]),
      hasAudio: (_) => false,
    );
    expect(
      job.graph,
      contains('anullsrc=r=48000:cl=stereo,atrim=end_sample=192000[aout]'),
    );
  });

  test('4× sound chains atempo steps within 0.5…2', () {
    final job = _job(
      TimelineProject(id: 'p', clips: [_video('a', end: 8, speed: 4)]),
    );
    expect(job.graph, contains('asetpts=PTS-STARTPTS,atempo=2,atempo=2,apad'));
  });

  test('graph loading option follows the ffmpeg version', () {
    expect(
      FfmpegTimelineRenderer.graphOptionFor(
        'ffmpeg version 6.1.1\nlibavfilter     9. 12.100 /  9. 12.100',
      ),
      '-filter_complex_script',
    );
    expect(
      FfmpegTimelineRenderer.graphOptionFor('libavfilter    10.  4.100'),
      '-/filter_complex',
    );
    expect(FfmpegTimelineRenderer.graphOptionFor(''), '-filter_complex_script');
  });
}
