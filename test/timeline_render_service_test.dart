import 'dart:io';
import 'dart:typed_data';

import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/video_lut_baker.dart';
import 'package:aqua_recover/core/timeline/timeline_grade_baker.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_render_plan.dart';
import 'package:aqua_recover/core/timeline/timeline_render_service.dart';
import 'package:aqua_recover/core/timeline/timeline_textures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The project the contract notes use: two main clips (one at 2× with grain,
/// vignette, and a fade out), a popping photo, a title, a video overlay, and
/// music.
TimelineProject _example() => TimelineProject(
  id: 'example',
  clips: [
    const TimelineClip(
      id: 'clipA',
      path: '/media/a.mov',
      kind: TimelineClipKind.video,
      sourceStart: 2,
      sourceEnd: 10,
      sourceDuration: 30,
    ),
    TimelineClip(
      id: 'clipB',
      path: '/media/b.mov',
      kind: TimelineClipKind.video,
      sourceStart: 0,
      sourceEnd: 8,
      sourceDuration: 8,
      speed: 2,
      fadeOut: 1,
      transition: ClipTransition.crossfade,
      effects: [ClipEffect(EffectType.grain), ClipEffect(EffectType.vignette)],
    ),
  ],
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
      title: TitleSpec(text: 'Blue Hole', style: TitleStyle.outline),
    ),
    TimelineOverlay(
      id: 'pip',
      kind: OverlayKind.video,
      path: '/media/pip.mov',
      start: 4,
      sourceStart: 1,
      sourceEnd: 4,
      centerX: 0.8,
      centerY: 0.8,
      widthFraction: 0.3,
      mediaAspect: 16 / 9,
      volume: 0.5,
    ),
  ],
  audioClips: const [
    TimelineAudioClip(
      id: 'music',
      name: 'Reef',
      path: '/media/music.m4a',
      sourceDuration: 120,
      volume: 0.7,
      fadeOut: 2,
    ),
  ],
);

class _FakeSampler implements ClipFrameSampler {
  final List<TimelineClip> requests = [];

  @override
  Future<List<Uint8List>> framesFor(TimelineClip clip) async {
    requests.add(clip);
    final frame = img.Image(width: 8, height: 8);
    img.fill(frame, color: img.ColorRgb8(40, 110, 140));
    return [img.encodePng(frame)];
  }
}

Map<String, Object?> _map(Object? value) => (value! as Map).cast();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nativeArguments v2', () {
    final plan = TimelineCompiler.compile(_example());
    final generated = {
      for (final layer in plan.layers)
        if (layer.source is GeneratedSource) layer.id: '/tmp/${layer.id}.png',
    };
    final args = TimelineRenderService.planArguments(
      plan,
      outputPath: '/out/movie.mp4',
      generatedPaths: generated,
    );

    test('top level', () {
      expect(args.keys, [
        'version',
        'outputPath',
        'width',
        'height',
        'frameRate',
        'duration',
        'clips',
        'layers',
        'audio',
      ]);
      expect(args['version'], 2);
      expect(args['outputPath'], '/out/movie.mp4');
      expect(
        (args['width'], args['height'], args['frameRate']),
        (1920, 1080, 30),
      );
      expect(args['duration'], closeTo(11.4, 1e-9));
    });

    test('clips', () {
      final clips = (args['clips']! as List).map(_map).toList();
      expect(clips, hasLength(2));
      expect(clips[1].keys, [
        'id',
        'path',
        'kind',
        'start',
        'duration',
        'overlapIn',
        'sourceStart',
        'sourceDuration',
        'speed',
        'fit',
        'keys',
        'grade',
        'look',
        'filters',
      ]);
      final b = clips[1];
      expect(b['kind'], 'video');
      expect(b['start'], closeTo(7.4, 1e-9));
      expect((b['duration'], b['overlapIn']), (4.0, 0.6));
      expect(
        (b['sourceStart'], b['sourceDuration'], b['speed']),
        (0.0, 8.0, 2.0),
      );
      expect(b['fit'], 'contain');
      expect(b['keys'], isEmpty);
      final filters = _map(b['filters']);
      expect(filters['colorMatrix'], isNull);
      expect(filters['grain'], closeTo(0.018, 1e-12));
      expect((filters['blurSigma'], filters['sharpen']), (0.0, 0.0));
      expect(b.containsKey('motion'), isFalse);
      expect(b.containsKey('muted'), isFalse);
      expect(b.containsKey('lut'), isFalse);
    });

    test('layers', () {
      final layers = (args['layers']! as List).map(_map).toList();
      expect(layers.map((l) => l['id']), [
        'clipB.fx1-vignette',
        'clipB.fadeOut',
        'photo',
        'pip',
        'title',
      ]);
      final vignette = layers[0];
      expect(vignette['kind'], 'image');
      expect(vignette['path'], '/tmp/clipB.fx1-vignette.png');
      expect(vignette['ownerClipId'], 'clipB');
      final fade = layers[1];
      expect(fade['kind'], 'color');
      expect(fade['color'], 0xFF000000);
      expect(fade.containsKey('path'), isFalse);
      expect(fade['start'], closeTo(10.4, 1e-9));
      final photo = layers[2];
      expect(photo['kind'], 'image');
      expect(photo['path'], '/media/turtle.jpg');
      expect(photo.containsKey('grade'), isFalse);
      final keys = (photo['keys']! as List).map(_map).toList();
      expect(keys.first.keys, ['t', 'x', 'y', 'w', 'h', 'rotation', 'opacity']);
      expect(keys.first['opacity'], 0.0);
      expect(layers[3]['kind'], 'video');
      expect(layers[3]['sourceStart'], 1.0);
      expect(layers[4]['kind'], 'image');
      expect(layers[4]['path'], '/tmp/title.png');
      for (final layer in layers) {
        expect(layer['filters'], isA<Map<String, Object?>>());
        for (final field in ['start', 'duration', 'sourceStart', 'speed']) {
          expect(layer[field], isA<double>(), reason: '${layer['id']} $field');
        }
      }
    });

    test('audio', () {
      final audio = (args['audio']! as List).map(_map).toList();
      expect(audio.map((a) => a['id']), ['clipA', 'clipB', 'pip', 'music']);
      expect(audio.first.keys, [
        'id',
        'path',
        'origin',
        'lane',
        'start',
        'duration',
        'sourceStart',
        'sourceDuration',
        'speed',
        'volume',
        'fadeIn',
        'fadeOut',
      ]);
      final b = audio[1];
      expect(
        (b['speed'], b['sourceDuration'], b['fadeIn'], b['fadeOut']),
        (2.0, 8.0, 0.6, 1.0),
      );
      final music = audio[3];
      expect(music['origin'], 'track');
      expect(music['sourceDuration'], closeTo(11.4, 1e-9));
      expect(music['fadeOut'], 2.0);
      expect(audio.map((a) => a['lane']), [0, 2, 2, 1]);
    });

    test('generated layers need their PNG', () {
      expect(
        () => TimelineRenderService.planArguments(plan, outputPath: '/o.mp4'),
        throwsStateError,
      );
    });

    test('Android cubes ride along by clip and layer id', () {
      final cube = TimelineGradeBaker.identityCube(2);
      final withCubes = TimelineRenderService.planArguments(
        plan,
        outputPath: '/o.mp4',
        generatedPaths: generated,
        cubes: {'clipA': cube, 'pip': cube},
      );
      final clip = _map((withCubes['clips']! as List).first);
      expect(clip['lutSize'], 2);
      expect(clip['lut'], isA<Int32List>());
      final pip = (withCubes['layers']! as List)
          .map(_map)
          .singleWhere((l) => l['id'] == 'pip');
      expect(pip['lutSize'], 2);
    });

    test('project overload compiles without generated layers', () {
      final args = TimelineRenderService.nativeArguments(
        TimelineProject(id: 'p', clips: [_example().clips.first]),
        outputPath: '/o.mp4',
      );
      expect(args['version'], 2);
      expect(args['layers'], isEmpty);
    });
  });

  test('writeGeneratedSources materialises every generated layer', () async {
    final dir = await Directory.systemTemp.createTemp('aq_generated');
    addTearDown(() => dir.delete(recursive: true));
    final plan = TimelineCompiler.compile(
      _example(),
      titleAspect: titleAspectRatio,
    );
    final paths = await TimelineRenderService.writeGeneratedSources(
      plan,
      GeneratedTextureCache(directory: () async => dir),
    );
    expect(paths.keys, ['clipB.fx1-vignette', 'title']);
    for (final path in paths.values) {
      expect(File(path).existsSync(), isTrue);
    }
    final title = plan.layers.singleWhere((l) => l.id == 'title');
    final aspect = titleAspectRatio(
      const TitleSpec(text: 'Blue Hole', style: TitleStyle.outline),
      1920,
      1080,
    );
    expect(title.keys.single.w / title.keys.single.h, closeTo(aspect, 1e-9));
    // Every layer can now be sent.
    TimelineRenderService.planArguments(
      plan,
      outputPath: '/o.mp4',
      generatedPaths: paths,
    );
  });

  group('TimelineGradeBaker', () {
    test('identity cube maps colours to themselves', () {
      final cube = TimelineGradeBaker.identityCube(3);
      expect(cube.rgb.sublist(0, 9), [0, 0, 0, 128, 0, 0, 255, 0, 0]);
      expect(cube.rgb.sublist(cube.rgb.length - 3), [255, 255, 255]);
    });

    test('applies a colour matrix after the cube, clamped', () {
      final mono = TimelineGradeBaker.applyColorMatrix(
        TimelineGradeBaker.identityCube(2),
        ColorMatrices.full(EffectType.mono),
      );
      // Entry 1 is pure red.
      expect(mono.rgb.sublist(3, 6), [54, 54, 54]);
      final lifted = TimelineGradeBaker.applyColorMatrix(
        TimelineGradeBaker.identityCube(2),
        ColorMatrices.full(EffectType.deepBlue),
      );
      // White: blue 1.04 + 0.05 clamps to 1.
      expect(lifted.rgb.sublist(lifted.rgb.length - 3), [199, 255, 255]);
      expect(
        () => TimelineGradeBaker.applyColorMatrix(lifted, const [1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('caches the grade and re-applies only the matrix', () async {
      final sampler = _FakeSampler();
      final baker = TimelineGradeBaker(sampler, cubeSize: 5);
      final clip = _example().clips.first;
      final plain = await baker.cubeFor(clip);
      final mono = await baker.cubeFor(
        clip,
        colorMatrix: ColorMatrices.full(EffectType.mono),
      );
      expect(sampler.requests, hasLength(1));
      expect(mono.size, 5);
      expect(mono.rgb, isNot(plain.rgb));
      for (var j = 0; j < mono.rgb.length; j += 3) {
        expect(mono.rgb[j], mono.rgb[j + 1]);
        expect(mono.rgb[j + 1], mono.rgb[j + 2]);
      }
    });

    test('layer cubes only when a layer changes colour', () async {
      final sampler = _FakeSampler();
      final baker = TimelineGradeBaker(sampler, cubeSize: 5);
      const plain = PlanLayer(
        id: 'p',
        kind: PlanLayerKind.image,
        source: FileSource('/media/p.png'),
        start: 0,
        duration: 1,
        keys: [LayerKey(t: 0, x: 0, y: 0, w: 1, h: 1)],
      );
      expect(await baker.cubeForLayer(plain), isNull);
      const color = PlanLayer(
        id: 'c',
        kind: PlanLayerKind.color,
        source: ColorSource(0xFF000000),
        start: 0,
        duration: 1,
        keys: [LayerKey(t: 0, x: 0, y: 0, w: 1, h: 1)],
      );
      expect(await baker.cubeForLayer(color), isNull);

      final matrixOnly = PlanLayer(
        id: 'm',
        kind: PlanLayerKind.image,
        source: const FileSource('/media/m.png'),
        start: 0,
        duration: 1,
        keys: const [LayerKey(t: 0, x: 0, y: 0, w: 1, h: 1)],
        filters: PlanFilters(colorMatrix: ColorMatrices.full(EffectType.mono)),
      );
      final cube = (await baker.cubeForLayer(matrixOnly))!;
      // Entry 1 of a 5³ cube is red 0.25: luma 0.053.
      expect(cube.rgb.sublist(3, 6), [14, 14, 14]);
      expect(sampler.requests, isEmpty);

      final graded = PlanLayer(
        id: 'g',
        kind: PlanLayerKind.video,
        source: const FileSource('/media/g.mov'),
        start: 1,
        duration: 2,
        sourceStart: 3,
        sourceDuration: 4,
        speed: 2,
        keys: const [LayerKey(t: 0, x: 0, y: 0, w: 1, h: 1)],
        grade: RestorationPreset.vivid.settings,
        look: LutProfile.blueWater,
      );
      expect(await baker.cubeForLayer(graded), isA<ColorCube>());
      final request = sampler.requests.single;
      expect(request.path, '/media/g.mov');
      expect(request.isVideo, isTrue);
      expect((request.sourceStart, request.sourceEnd), (3, 7));
      expect(request.look.kind, LutKind.blueWater);
    });

    test('bakeCubes covers main clips and coloured layers', () async {
      final sampler = _FakeSampler();
      final project = _example().copyWith(
        overlays: [
          ..._example().overlays,
          TimelineOverlay(
            id: 'sepia',
            kind: OverlayKind.image,
            path: '/media/s.png',
            effects: [ClipEffect(EffectType.sepia)],
          ),
        ],
      );
      final plan = TimelineCompiler.compile(project);
      final progress = <double>[];
      final cubes = await TimelineRenderService.bakeCubes(
        project,
        plan,
        TimelineGradeBaker(sampler, cubeSize: 5),
        onProgress: progress.add,
      );
      expect(cubes.keys, ['clipA', 'clipB', 'sepia']);
      expect(progress.last, 1);
    });
  });
}
