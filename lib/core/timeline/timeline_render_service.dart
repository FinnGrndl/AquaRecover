import 'dart:io';

import 'package:flutter/services.dart';

import '../processing/ffmpeg_video_backend.dart';
import '../processing/video_lut_baker.dart';
import 'ffmpeg_timeline_renderer.dart';
import 'timeline_grade_baker.dart';
import 'timeline_project.dart';
import 'timeline_render_plan.dart';
import 'timeline_textures.dart';

enum TimelineRenderBackend {
  /// AVAssetWriter + Core Image with the full AquaRecover grade per frame.
  apple,

  /// Media3 Transformer with baked colour tables.
  android,

  /// One ffmpeg filter graph with baked colour tables.
  ffmpeg,

  none,
}

/// Renders a [TimelineProject] to a movie with the best backend the platform
/// has, reporting progress from 0 to 1.
class TimelineRenderService {
  TimelineRenderService({
    MethodChannel? channel,
    GeneratedTextureCache? textures,
  }) : _channel = channel ?? const MethodChannel('aqua_recover/timeline'),
       _textures = textures ?? GeneratedTextureCache();

  /// Version of the `renderTimeline` arguments.
  static const contractVersion = 2;

  final MethodChannel _channel;
  final GeneratedTextureCache _textures;
  FfmpegTimelineRenderer? _ffmpeg;
  TimelineGradeBaker? _androidBaker;
  void Function(double progress)? _onProgress;
  bool _cancelled = false;

  static TimelineRenderBackend backendFor(
    String operatingSystem, {
    bool ffmpegAvailable = false,
  }) => switch (operatingSystem) {
    'ios' || 'macos' => TimelineRenderBackend.apple,
    'android' => TimelineRenderBackend.android,
    _ when ffmpegAvailable => TimelineRenderBackend.ffmpeg,
    _ => TimelineRenderBackend.none,
  };

  static TimelineRenderBackend get currentBackend => backendFor(
    Platform.operatingSystem,
    ffmpegAvailable:
        !Platform.isIOS &&
        !Platform.isAndroid &&
        !Platform.isMacOS &&
        FfmpegVideoBackend.locate() != null,
  );

  /// Arguments for the native renderers (contract v2): [project] compiled by
  /// [TimelineCompiler] into absolute times, rectangles, keys, filters, and
  /// audio segments, so native code never re-derives layout or animation.
  /// See [planArguments].
  static Map<String, Object?> nativeArguments(
    TimelineProject project, {
    required String outputPath,
    Map<String, ColorCube> cubes = const {},
    Map<String, String> generatedPaths = const {},
  }) => planArguments(
    TimelineCompiler.compile(project),
    outputPath: outputPath,
    cubes: cubes,
    generatedPaths: generatedPaths,
  );

  /// The `renderTimeline` arguments of [plan]. [cubes] are Android colour
  /// tables (grade, look, and colour matrix baked) keyed by clip or layer id;
  /// [generatedPaths] are the PNGs of generated layers keyed by layer id (see
  /// [writeGeneratedSources]), which are then sent as `image` layers.
  static Map<String, Object?> planArguments(
    TimelineRenderPlan plan, {
    required String outputPath,
    Map<String, ColorCube> cubes = const {},
    Map<String, String> generatedPaths = const {},
  }) {
    Map<String, Object?> lut(String id) => switch (cubes[id]) {
      final cube? => {'lutSize': cube.size, 'lut': cube.toArgb()},
      null => const {},
    };
    return {
      'version': contractVersion,
      'outputPath': outputPath,
      'width': plan.width,
      'height': plan.height,
      'frameRate': plan.frameRate,
      'duration': plan.duration,
      'clips': [
        for (final clip in plan.clips) {...clip.toJson(), ...lut(clip.id)},
      ],
      'layers': [
        for (final layer in plan.layers)
          {...layer.toJson(path: generatedPaths[layer.id]), ...lut(layer.id)},
      ],
      'audio': [for (final segment in plan.audio) segment.toJson()],
    };
  }

  /// Rasterises every generated title and texture of [plan] through [cache]
  /// and returns each generated layer's PNG path by layer id.
  static Future<Map<String, String>> writeGeneratedSources(
    TimelineRenderPlan plan,
    GeneratedTextureCache cache,
  ) async {
    final paths = <String, String>{};
    for (final layer in plan.layers) {
      if (layer.source case GeneratedSource(:final spec)) {
        paths[layer.id] = await cache.pathFor(spec);
      }
    }
    return paths;
  }

  /// Android colour tables: one per main clip, plus one per video or image
  /// layer that has a grade, look, or colour matrix.
  static Future<Map<String, ColorCube>> bakeCubes(
    TimelineProject project,
    TimelineRenderPlan plan,
    TimelineGradeBaker baker, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final cubes = <String, ColorCube>{};
    final clips = {for (final clip in project.clips) clip.id: clip};
    final steps = plan.clips.length + plan.layers.length;
    var done = 0;
    void step() => onProgress?.call(++done / (steps == 0 ? 1 : steps));
    for (final planClip in plan.clips) {
      if (isCancelled?.call() ?? false) throw const TimelineRenderCancelled();
      cubes[planClip.id] = await baker.cubeFor(
        clips[planClip.id]!,
        colorMatrix: planClip.filters.colorMatrix,
      );
      step();
    }
    for (final layer in plan.layers) {
      if (isCancelled?.call() ?? false) throw const TimelineRenderCancelled();
      if (await baker.cubeForLayer(layer) case final cube?) {
        cubes[layer.id] = cube;
      }
      step();
    }
    return cubes;
  }

  Future<String> render(
    TimelineProject project, {
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (project.clips.isEmpty) {
      throw StateError('Add at least one photo or clip to the timeline.');
    }
    _cancelled = false;
    final backend = currentBackend;
    switch (backend) {
      case TimelineRenderBackend.none:
        throw UnsupportedError(
          'Timeline export needs iOS, macOS, Android, or ffmpeg on this computer.',
        );
      case TimelineRenderBackend.ffmpeg:
        final plan = TimelineCompiler.compile(
          project,
          titleAspect: titleAspectRatio,
        );
        final generated = await writeGeneratedSources(plan, _textures);
        if (_cancelled) throw const TimelineRenderCancelled();
        final renderer = _ffmpeg ??= FfmpegTimelineRenderer(
          FfmpegVideoBackend(FfmpegVideoBackend.locate()!),
        );
        return renderer.render(
          project,
          plan: plan,
          generatedPaths: generated,
          outputPath: outputPath,
          onProgress: onProgress,
        );
      case TimelineRenderBackend.apple:
      case TimelineRenderBackend.android:
        final plan = TimelineCompiler.compile(
          project,
          titleAspect: titleAspectRatio,
        );
        final generated = await writeGeneratedSources(plan, _textures);
        if (_cancelled) throw const TimelineRenderCancelled();
        var cubes = const <String, ColorCube>{};
        if (backend == TimelineRenderBackend.android) {
          cubes = await bakeCubes(
            project,
            plan,
            _androidBaker ??= TimelineGradeBaker(_AndroidSampler(_channel)),
            onProgress: (value) => onProgress?.call(0.1 * value),
            isCancelled: () => _cancelled,
          );
          if (_cancelled) throw const TimelineRenderCancelled();
        }
        _onProgress = onProgress;
        _channel.setMethodCallHandler(_handleNativeCall);
        try {
          final path = await _channel.invokeMethod<String>(
            'renderTimeline',
            planArguments(
              plan,
              outputPath: outputPath,
              cubes: cubes,
              generatedPaths: generated,
            ),
          );
          if (path == null || path.isEmpty) {
            throw StateError('The timeline render returned no file.');
          }
          return path;
        } on PlatformException catch (error) {
          if (error.code == 'CANCELLED') throw const TimelineRenderCancelled();
          throw StateError(
            'Timeline render failed. ${error.message ?? error.code}',
          );
        } finally {
          _onProgress = null;
        }
    }
  }

  void cancel() {
    _cancelled = true;
    _ffmpeg?.cancel();
    if (currentBackend
        case TimelineRenderBackend.apple || TimelineRenderBackend.android) {
      _channel.invokeMethod<void>('cancelTimeline').catchError((Object _) {});
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'progress' && call.arguments is num) {
      final value = (call.arguments as num).toDouble();
      final scaled = currentBackend == TimelineRenderBackend.android
          ? 0.1 + 0.9 * value
          : value;
      _onProgress?.call(scaled.clamp(0.0, 1.0));
    }
    return null;
  }
}

class _AndroidSampler implements ClipFrameSampler {
  const _AndroidSampler(this.timeline);

  final MethodChannel timeline;
  static const _video = MethodChannel('aqua_recover/video');

  @override
  Future<List<Uint8List>> framesFor(TimelineClip clip) async {
    if (!clip.isVideo) {
      final still = await timeline.invokeMethod<Uint8List>('stillFrame', {
        'path': clip.path,
        'maxDimension': VideoLutBaker.sampleMaxDimension,
      });
      if (still == null) throw StateError('Could not read ${clip.path}.');
      return [still];
    }
    final frames = await _video.invokeListMethod<Uint8List>('sampleFrames', {
      'inputPath': clip.path,
      'count': 4,
      'maxDimension': VideoLutBaker.sampleMaxDimension,
      'startSeconds': clip.sourceStart,
      'endSeconds': clip.sourceStart + clip.sourceSpan,
    });
    return frames ?? const [];
  }
}
